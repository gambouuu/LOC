#include <HardwareSerial.h>
#include <math.h>
#include <base64.h>

HardwareSerial modemSerial(1); // UART1 para A7670E

//#define MODEM_RX 16
//#define MODEM_TX 17
#define MODEM_RX 22
#define MODEM_TX 23
//#define MODEM_PWRKEY 4

const char* mqtt_broker_ip = "IP_SERVER";
const char* mqtt_topic = "ubi/campers";

bool modemEncendido = false;
bool mqttConectado = false;
bool gnssOn = false;
bool enMovimiento = false;

unsigned long lastPublish = 0;
unsigned long lastCheck = 0;
unsigned long ultimoFixValido = 0;

double lastLat = 0, lastLng = 0;
float lastHdop = 99.9;
String lastHora = "", lastPayload = "";

const unsigned long MAX_SIN_FIX = 30 * 60 * 1000UL;

// ---------- FUNCIONES DE SOPORTE ----------

/*void powerOnModem() {
  Serial.println("[MODEM] Encendiendo módem...");
  pinMode(MODEM_PWRKEY, OUTPUT);
  digitalWrite(MODEM_PWRKEY, LOW);
  delay(1000);
  digitalWrite(MODEM_PWRKEY, HIGH);
  delay(1000);
  digitalWrite(MODEM_PWRKEY, LOW);
  delay(8000);
  modemEncendido = true;
}*/

String sendAT(const String& cmd, const String& expected = "OK", uint32_t timeout = 8000) {
  modemSerial.flush();
  Serial.println("Enviando comando: " + cmd);
  modemSerial.println(cmd);

  String resp = "";
  uint32_t start = millis();

  while (millis() - start < timeout) {
    while (modemSerial.available()) {
      char c = modemSerial.read();
      resp += c;
      Serial.write(c);

      // Detectar reinicio
      if (resp.indexOf("*ATREADY: 1") != -1) {
        Serial.println("⚠️ Módem reiniciado detectado, reconfigurando...");
        modemSerial.flush();
        delay(5000);
        sendAT("ATE0");
        sendAT("AT+CFUN=1");
        delay(2000);
        sendAT("AT+CGATT=1");
        sendAT("AT+CGDCONT=1,\"IP\",\"comgate.m2m\"");
        sendAT("AT+CGACT=1,1");
        delay(2000);
        sendAT("AT+CGNSSPWR=0");
        delay(500);
        sendAT("AT+CGNSSPWR=1");
        gnssOn = true;
        mqttConectado = false;
        return "";
      }

      // Detectar caída de red de datos
      if (resp.indexOf("+CGEV: ME PDN DEACT") != -1) {
        Serial.println("Conexión de datos caída detectada");
        mqttConectado = false;
        return resp;
      }

      if (resp.indexOf(expected) != -1) return resp;
      if (resp.indexOf("ERROR") != -1) return "";
    }
    delay(5);
  }

  Serial.println("Timeout en comando: " + cmd);
  return "";
}

bool waitForCREG() {
  for (int i = 0; i < 10; i++) {
    String r = sendAT("AT+CREG?", "OK", 2000);
    if (r.indexOf("+CREG: 0,1") != -1 || r.indexOf("+CREG: 0,5") != -1) {
      Serial.println("Red registrada correctamente");
      return true;
    }
    delay(1000);
  }
  Serial.println("No hay red móvil disponible");
  return false;
}

bool conectarRed() {
  sendAT("ATE0");
  sendAT("AT+CGDCONT=1,\"IP\",\"comgate.m2m\"");
  sendAT("AT+CFUN=1");
  delay(1000);
  sendAT("AT+COPS=0", "OK", 10000);
  bool ok = waitForCREG() && sendAT("AT+CGATT=1");
  if (!ok) {
    Serial.println("Esperando recuperación de red...");
    delay(1000);
  }
  return ok;
}


bool waitForGnssReady(uint32_t timeout_ms = 15000) {
  uint32_t t0 = millis();
  while (millis() - t0 < timeout_ms) {
    String resp = sendAT("AT+CGNSSPWR?", "OK", 2000);
    if (resp.indexOf("+CGNSSPWR: 1") != -1) return true;
    delay(1000);
  }
  return false;
}

bool ensureGnssOn() {
  if (gnssOn) return true;

  String pdp = sendAT("AT+CGACT?", "OK", 2000);
  if (pdp.indexOf("+CGACT: 1,1") != -1) {
    Serial.println("⌛ Esperando estabilidad de red antes de activar GNSS...");
    delay(1000);
  }
  for (int i = 0; i < 3; i++) {
    String resp = sendAT("AT+CGNSSPWR=1", "OK", 5000);
    if (resp.indexOf("OK") != -1) {
      if (waitForGnssReady()) {
        Serial.println("GNSS encendido y listo");
        gnssOn = true;
        return true;
      }
    }
    Serial.println("GNSS no respondió, reintentando...");
    sendAT("AT+CGNSSPWR=0", "OK", 2000);
    delay(1000);
  }

  Serial.println("Error al activar GNSS");
  return false;
}


String readGnssInfo() {
  modemSerial.flush();
  modemSerial.println("AT+CGNSSINFO");
  String resp = "";
  uint32_t start = millis();
  while (millis() - start < 15000) {
    while (modemSerial.available()) {
      char c = modemSerial.read();
      resp += c;
      Serial.write(c);
      if (resp.indexOf("OK") != -1 || resp.indexOf("ERROR") != -1)
        return resp;
    }
    delay(5);
  }
  return "";
}

double calcularDistancia(double lat1, double lon1, double lat2, double lon2) {
  const double R = 6371000.0;
  double dLat = radians(lat2 - lat1);
  double dLon = radians(lon2 - lon1);
  double a = sin(dLat / 2) * sin(dLat / 2) +
             cos(radians(lat1)) * cos(radians(lat2)) *
             sin(dLon / 2) * sin(dLon / 2);
  double c = 2 * atan2(sqrt(a), sqrt(1 - a));
  return R * c;
}

bool initMQTT() {
  if (!conectarRed()) return false;

  // Esperar confirmación de IP asignada
  for (int i = 0; i < 10; i++) {
    String ip = sendAT("AT+CGPADDR=1", "OK", 2000);
    if (ip.indexOf("+CGPADDR: 1,") != -1) break;
    Serial.println("Esperando IP asignada...");
    delay(1000);
  }

  sendAT("AT+CMQTTSTOP");
  delay(500);
  if (!sendAT("AT+CMQTTSTART")) return false;
  delay(500);
  if (!sendAT("AT+CMQTTACCQ=0,\"ESP32GPS\"")) return false;
  String cmd = "AT+CMQTTCONNECT=0,\"tcp://" + String(mqtt_broker_ip) + ":PUERTO\",60,1,\"USUARIO\",\"CONTRASEÑA\"";
  if (!sendAT(cmd, "+CMQTTCONNECT: 0,0", 15000)) {
    Serial.println("Error conectando MQTT");
    return false;
  }
  Serial.println("Esperando estabilización MQTT...");
  delay(1000);
  mqttConectado = true;
  Serial.println("MQTT conectado correctamente");
  return true;
}


String generarCSV(String hora, String lat, String lng, String alt, String hdopStr) {
  String csv = "USUARIO," + hora + "," + lat + "," + lng + "," + alt + "," + hdopStr + ",";
  csv += enMovimiento ? "1" : "0";
  return csv;
}

String cifrarCSV(String csv) {
  String clave = "CLAVE";
  String cifrado = "";
  for (int i = 0; i < csv.length(); i++)
    cifrado += (char)(csv[i] ^ clave[i % clave.length()]);
  return base64::encode(cifrado);
}

bool publicar(String payload) {
  //if (!modemEncendido) powerOnModem();
  if (!mqttConectado) mqttConectado = initMQTT();
  if (!mqttConectado) return false;

  String ip = sendAT("AT+CGPADDR=1", "OK", 2000);
  if (ip.indexOf("0.0.0.0") != -1) {
    Serial.println("Sin IP, reintentando conexión de datos...");
    conectarRed();
    mqttConectado = initMQTT();
  }

  Serial.println("Esperando estabilización MQTT...");
  delay(1000);

  int len = payload.length();
  int topicLen = String(mqtt_topic).length();

  if (!sendAT("AT+CMQTTTOPIC=0," + String(topicLen), ">", 5000)) return false;
  modemSerial.print(mqtt_topic);
  delay(200);

  if (!sendAT("AT+CMQTTPAYLOAD=0," + String(len), ">", 5000)) return false;
  modemSerial.print(payload);
  delay(200);

  String pubResp = sendAT("AT+CMQTTPUB=0,1,60", "+CMQTTPUB: 0,0", 20000);
  if (pubResp.indexOf("+CMQTTPUB: 0,0") == -1) {
    Serial.println("Publicación fallida, reintentando...");
    mqttConectado = false;
    delay(1000);
    mqttConectado = initMQTT();
    if (mqttConectado) {
      pubResp = sendAT("AT+CMQTTPUB=0,1,60", "+CMQTTPUB: 0,0", 20000);
      if (pubResp.indexOf("+CMQTTPUB: 0,0") != -1) {
        Serial.println("Reintento exitoso");
        return true;
      }
    }
    Serial.println("Fallo final publicando MQTT");
    sendAT("AT+CMQTTDISC=0,60");
    sendAT("AT+CMQTTREL=0");
    sendAT("AT+CMQTTSTOP");
    mqttConectado = false;
    delay(1000);
    return false;
  }

  Serial.println("📡 Payload publicado correctamente");
  return true;
}


void comprobarReinicioPorGPS() {
  if (millis() - ultimoFixValido > MAX_SIN_FIX) {
    Serial.println("Reinicio: más de 30 min sin fix GPS válido");
    delay(1000);
    esp_restart();
  }
}

bool isSafeGpio(int g) {
  // Evitar: GPIO6-11 (flash), 34-39 (solo entrada, ok pero sin pullups internos en algunos),
  // y pines de strapping delicados: 0,2,4,5,12,15 (depende de la placa/boot).
  if (g >= 6 && g <= 11) return false;     // flash
  if (g == 0 || g == 2 || g == 4 || g == 5 || g == 12 || g == 15) return false; // strapping
  return true;
}

void parkUnusedPins() {
  bool used[40] = {false};
  used[MODEM_RX] = true;
  used[MODEM_TX] = true;

  for (int g = 0; g < 40; g++) {
    if (!isSafeGpio(g)) continue;
    if (used[g]) continue;

    pinMode(g, INPUT_PULLDOWN);
  }

  pinMode(MODEM_RX, INPUT_PULLUP);
}


// ---------- SETUP ----------

void setup() {
  Serial.begin(115200);
  modemSerial.begin(115200, SERIAL_8N1, MODEM_RX, MODEM_TX);
  delay(2000);
  ensureGnssOn();
  lastCheck = millis();
  lastPublish = 0; 
  ultimoFixValido = millis();
  //pinMode(MODEM_RX, INPUT_PULLUP);
  parkUnusedPins();
}

// ---------- LOOP PRINCIPAL ----------

void loop() {
  unsigned long now = millis();

  if (millis() - ultimoFixValido > (10UL * 60 * 1000UL)) {
    Serial.println("Más de 10 minutos sin fix, reiniciando GNSS...");
    sendAT("AT+CGNSSPWR=0", "OK", 3000);
    delay(2000);
    sendAT("AT+CGNSSPWR=1", "OK", 5000);
    ultimoFixValido = millis();
  }


  if (now - lastCheck > 15000UL) {
    lastCheck = now;
    ensureGnssOn();

    String raw = readGnssInfo();
    static int gnssFails = 0;

    if (raw == "" || raw.indexOf("+CGNSSINFO:") == -1) {
      gnssFails++;
      if (gnssFails >= 3) {
        Serial.println("GNSS parece colgado, reiniciando subsistema...");
        sendAT("AT+CGNSSPWR=0", "OK", 3000);
        delay(1000);
        sendAT("AT+CGNSSPWR=1", "OK", 5000);
        gnssFails = 0;
      }
      Serial.println("Error o sin respuesta GNSS");
      comprobarReinicioPorGPS();
      return;
    } else {
      gnssFails = 0;
    }

    int idx = raw.indexOf("+CGNSSINFO:");
    String data = raw.substring(idx + 12);
    data.trim();

    String fields[20];
    int fCount = 0, start = 0;
    while (fCount < 18) {
      int comma = data.indexOf(',', start);
      if (comma == -1) {
        fields[fCount++] = data.substring(start);
        break;
      }
      fields[fCount++] = data.substring(start, comma);
      start = comma + 1;
    }

    if (fields[5] == "" || fields[7] == "") {
      Serial.println("Sin fix GPS válido aún");
      comprobarReinicioPorGPS();
      return;
    }

    String lat = fields[5];
    String latDir = fields[6];
    String lon = fields[7];
    String lonDir = fields[8];
    String alt = fields[11];
    String fechaHora = fields[10];
    String hora = fechaHora.length() >= 6 ? fechaHora.substring(0,2)+":"+fechaHora.substring(2,4)+":"+fechaHora.substring(4,6) : "??:??:??";
    float hdop = fields[15].toFloat();

    double currLat = lat.toFloat();
    if (latDir == "S") currLat *= -1;
    double currLng = lon.toFloat();
    if (lonDir == "W") currLng *= -1;

    double dist = calcularDistancia(lastLat, lastLng, currLat, currLng);
    bool ahoraMoviendo = dist > 50.0;

    Serial.println("\nGPS Fix válido");
    Serial.println("Lat: " + String(currLat, 8));
    Serial.println("Lon: " + String(currLng, 8));
    Serial.println("Hora: " + hora);
    Serial.println("HDOP: " + String(hdop));
    Serial.println("Distancia movida: " + String(dist));

    ultimoFixValido = millis();
    lastLat = currLat;
    lastLng = currLng;
    lastHora = hora;

    if (ahoraMoviendo != enMovimiento) {
      enMovimiento = ahoraMoviendo;
      Serial.println(enMovimiento ? "Movimiento detectado" : "Reposo");
      // Fuerza publicación inmediata al detectar movimiento
      if (enMovimiento) lastPublish = 0;
      else lastPublish = now;
    }

    String csv = generarCSV(hora, String(currLat,8), String(currLng,8), alt, String(hdop,1));
    String payload = cifrarCSV(csv);

    if ((enMovimiento && now - lastPublish > 15000UL && hdop <= 6 && payload != lastPayload) ||
        (!enMovimiento && now - lastPublish > 1800000UL)) {

      lastPublish = now;
      lastPayload = payload;

      if (!publicar(payload)) mqttConectado = false;

      if (!mqttConectado) {
        Serial.println("Reconectando red y MQTT tras caída...");
        conectarRed();
        mqttConectado = initMQTT();
      }

      if (!enMovimiento) {
        sendAT("AT+CMQTTDISC=0,60");
        sendAT("AT+CMQTTREL=0");
        sendAT("AT+CMQTTSTOP");
        mqttConectado = false;
      }
    }
  }
}
