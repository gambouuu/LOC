#include <HardwareSerial.h>
#include <math.h>
#include <base64.h>

HardwareSerial modemSerial(1); // UART1 para A7670E

#define MODEM_RX 16
#define MODEM_TX 17
#define MODEM_PWRKEY 4

const char* mqtt_broker_ip = "2.57.108.44";
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

void powerOnModem() {
  Serial.println("[MODEM] Encendiendo módem...");
  pinMode(MODEM_PWRKEY, OUTPUT);
  digitalWrite(MODEM_PWRKEY, LOW);
  delay(1000);
  digitalWrite(MODEM_PWRKEY, HIGH);
  delay(1000);
  digitalWrite(MODEM_PWRKEY, LOW);
  delay(8000); // Tiempo de arranque
  modemEncendido = true;
}

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
      if (resp.indexOf(expected) != -1) return resp;
      if (resp.indexOf("ERROR") != -1) return "";
    }
    delay(5);
  }

  Serial.println("⚠️ Timeout en comando: " + cmd);
  return "";
}

bool waitForCREG() {
  for (int i = 0; i < 10; i++) {
    String r = sendAT("AT+CREG?", "OK", 2000);
    if (r.indexOf("+CREG: 0,1") != -1 || r.indexOf("+CREG: 0,5") != -1) {
      Serial.println("📶 Red registrada correctamente");
      return true;
    }
    delay(3000);
  }
  Serial.println("❌ No hay red móvil disponible");
  return false;
}

bool conectarRed() {
  sendAT("ATE0"); // sin eco
  sendAT("AT+CGDCONT=1,\"IP\",\"comgate.m2m\"");
  sendAT("AT+CFUN=1");
  delay(5000);
  sendAT("AT+COPS=0", "OK", 10000);
  return waitForCREG() && sendAT("AT+CGATT=1");
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
  if (!sendAT("AT+CGNSSPWR=1")) return false;
  if (!waitForGnssReady()) return false;
  Serial.println("✅ GNSS encendido y listo");
  gnssOn = true;
  return true;
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
  sendAT("AT+CMQTTSTOP");
  delay(500);
  if (!sendAT("AT+CMQTTSTART")) return false;
  delay(500);
  if (!sendAT("AT+CMQTTACCQ=0,\"ESP32GPS\"")) return false;
  String cmd = "AT+CMQTTCONNECT=0,\"tcp://" + String(mqtt_broker_ip) + ":1883\",60,1,\"camper\",\"gamboalocalizador\"";
  if (!sendAT(cmd, "OK", 10000)) return false;
  mqttConectado = true;
  Serial.println("✅ MQTT conectado correctamente");
  return true;
}

String generarCSV(String hora, String lat, String lng, String alt, String hdopStr) {
  String csv = "Nomada," + hora + "," + lat + "," + lng + "," + alt + "," + hdopStr + ",";
  csv += enMovimiento ? "1" : "0";
  return csv;
}

String cifrarCSV(String csv) {
  String clave = "qu333yy-";
  String cifrado = "";
  for (int i = 0; i < csv.length(); i++)
    cifrado += (char)(csv[i] ^ clave[i % clave.length()]);
  return base64::encode(cifrado);
}

bool publicar(String payload) {
  if (!modemEncendido) powerOnModem();
  if (!mqttConectado) mqttConectado = initMQTT();
  if (!mqttConectado) return false;

  int len = payload.length();
  int topicLen = String(mqtt_topic).length();

  if (!sendAT("AT+CMQTTTOPIC=0," + String(topicLen), ">", 3000)) return false;
  modemSerial.print(mqtt_topic);
  delay(200);

  if (!sendAT("AT+CMQTTPAYLOAD=0," + String(len), ">", 3000)) return false;
  modemSerial.print(payload);
  delay(200);

  if (!sendAT("AT+CMQTTPUB=0,1,60", "+CMQTTPUB: 0,0", 5000)) return false;

  Serial.println("📡 Payload publicado correctamente");
  return true;
}

// Reinicio si no hay fix en mucho tiempo
void comprobarReinicioPorGPS() {
  if (millis() - ultimoFixValido > MAX_SIN_FIX) {
    Serial.println("⚠️ Reinicio: más de 30 min sin fix GPS válido");
    delay(1000);
    esp_restart();
  }
}

// ---------- SETUP ----------

void setup() {
  Serial.begin(115200);
  modemSerial.begin(115200, SERIAL_8N1, MODEM_RX, MODEM_TX);
  powerOnModem();
  delay(2000);
  ensureGnssOn();
  lastCheck = millis();
  lastPublish = millis();
  ultimoFixValido = millis();
}

// ---------- LOOP PRINCIPAL ----------

void loop() {
  unsigned long now = millis();

  if (now - lastCheck > 30000UL) {
    lastCheck = now;

    ensureGnssOn();

    String raw = readGnssInfo();
    if (raw == "" || raw.indexOf("+CGNSSINFO:") == -1) {
      Serial.println("❌ Error o sin respuesta GNSS");
      comprobarReinicioPorGPS();
      return;
    }

    int idx = raw.indexOf("+CGNSSINFO:");
    String data = raw.substring(idx + 12);
    data.trim();

    // Extraer campos
    String fields[20];
    int fCount = 0;
    int start = 0;
    while (fCount < 18) {
      int comma = data.indexOf(',', start);
      if (comma == -1) {
        fields[fCount++] = data.substring(start);
        break;
      }
      fields[fCount++] = data.substring(start, comma);
      start = comma + 1;
    }

    // Si no hay coordenadas, aún sin fix
    if (fields[5] == "" || fields[7] == "") {
      Serial.println("❌ Sin fix GPS válido aún");
      comprobarReinicioPorGPS();
      return;
    }

    // Extraer info
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
    bool ahoraMoviendo = dist > 30.0;

    Serial.println("\n🛰️ GPS Fix válido");
    Serial.println("📍 Lat: " + String(currLat, 8));
    Serial.println("📍 Lon: " + String(currLng, 8));
    Serial.println("⏱️ Hora: " + hora);
    Serial.println("📶 HDOP: " + String(hdop));
    Serial.println("📏 Distancia movida: " + String(dist));

    ultimoFixValido = millis();
    lastLat = currLat;
    lastLng = currLng;
    lastHora = hora;

    if (ahoraMoviendo != enMovimiento) {
      enMovimiento = ahoraMoviendo;
      Serial.println(enMovimiento ? "🟢 Movimiento detectado" : "🔴 Reposo");
      if (!enMovimiento) lastPublish = now;
    }

    String csv = generarCSV(hora, String(currLat,8), String(currLng,8), alt, String(hdop,1));
    String payload = cifrarCSV(csv);

    if ((enMovimiento && now - lastPublish > 40000UL && hdop <= 5.5 && payload != lastPayload) ||
        (!enMovimiento && now - lastPublish > 1800000UL)) {

      lastPublish = now;
      lastPayload = payload;

      if (!publicar(payload)) mqttConectado = false;

      if (!enMovimiento) {
        sendAT("AT+CMQTTDISC=0,60");
        sendAT("AT+CMQTTREL=0");
        sendAT("AT+CMQTTSTOP");
        mqttConectado = false;
      }
    }
  }
}
