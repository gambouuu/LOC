#include <WiFi.h>
#include <PubSubClient.h>
#include <HardwareSerial.h>
#include <math.h>
#include <base64.h>

// UART1 para el módulo A7670E (solo GNSS)
HardwareSerial modemSerial(1);

#define MODEM_RX 16
#define MODEM_TX 17
#define MODEM_PWRKEY 4

// WiFi
const char* ssid = "SSID";
const char* password = "PASSWD";

// MQTT
const char* mqtt_server = "IP_SERVER";
const int mqtt_port = 0000;
const char* mqtt_user = "USER";               
const char* mqtt_pass = "CONTRASEÑA";
const char* mqtt_topic = "ubi/campers";

WiFiClient espClient;
PubSubClient client(espClient);

unsigned long lastPublish = 0;
unsigned long lastCheck = 0;

bool enMovimiento = false;
bool modemEncendido = false;

float lastHdop = 99.9;
double lastLat = 0;
double lastLng = 0;

String lastHora = "";
String lastPayload = "";

unsigned long ultimoFixValido = 0;
const unsigned long MAX_SIN_FIX = 30 * 60 * 1000UL;

// ------------------------------------------------------------
// FUNCIONES
// ------------------------------------------------------------
void powerOnModem() {
  Serial.println("[MODEM] Encendiendo módem (solo GNSS)...");
  pinMode(MODEM_PWRKEY, OUTPUT);
  digitalWrite(MODEM_PWRKEY, LOW);
  delay(1000);
  digitalWrite(MODEM_PWRKEY, HIGH);
  delay(1000);
  digitalWrite(MODEM_PWRKEY, LOW);
  delay(10000);
  modemEncendido = true;
}

String sendAT(const String& cmd, const String& expected = "OK", int timeout = 8000) {
  modemSerial.println(cmd);
  unsigned long start = millis();
  String resp = "";

  while (millis() - start < timeout) {
    if (modemSerial.available()) {
      char c = modemSerial.read();
      resp += c;
      if (resp.indexOf(expected) != -1) return resp;
    } else delay(5);
  }

  Serial.println("Timeout esperando respuesta de: " + cmd);
  return resp;
}

void setup_wifi() {
  Serial.print("Conectando a WiFi: ");
  Serial.println(ssid);
  WiFi.mode(WIFI_STA);
  WiFi.begin(ssid, password);

  int intentos = 0;
  while (WiFi.status() != WL_CONNECTED && intentos < 30) {
    delay(1000);
    Serial.print(".");
    intentos++;
  }

  if (WiFi.status() == WL_CONNECTED) {
    Serial.println("\nWiFi conectado");
    Serial.print("IP: ");
    Serial.println(WiFi.localIP());
  } else {
    Serial.println("\nNo se pudo conectar a WiFi");
  }
}

void reconnectMQTT() {
  while (!client.connected()) {
    Serial.print("Conectando a MQTT...");
    if (client.connect("ESP32GPS", mqtt_user, mqtt_pass)) {
      Serial.println("Conectado a MQTT");
    } else {
      Serial.print("Fallo MQTT, rc=");
      Serial.print(client.state());
      Serial.println(" — Reintentando en 5s");
      delay(5000);
    }
  }
}

String generarCSV(String hora, String lat, String lng, String alt, String hdopStr) {
  String csv = "jG,";
  csv += hora + ",";
  csv += lat + ",";
  csv += lng + ",";
  csv += alt + ",";
  csv += hdopStr + ",";
  csv += enMovimiento ? "1" : "0";
  return csv;
}

String cifrarCSV(String csv) {
  String clave = "CLAVE";
  String cifrado = "";
  for (int i = 0; i < csv.length(); i++) {
    cifrado += (char)(csv[i] ^ clave[i % clave.length()]);
  }
  return base64::encode(cifrado);
}

bool publicar(String payload) {
  if (!client.connected()) reconnectMQTT();
  if (client.publish(mqtt_topic, payload.c_str())) {
    Serial.println("Payload publicado correctamente");
    return true;
  } else {
    Serial.println("Error al publicar payload");
    return false;
  }
}

double calcularDistancia(double lat1, double lon1, double lat2, double lon2) {
  const double R = 6371000;
  double dLat = radians(lat2 - lat1);
  double dLon = radians(lon2 - lon1);
  double a = sin(dLat / 2) * sin(dLat / 2) +
             cos(radians(lat1)) * cos(radians(lat2)) *
             sin(dLon / 2) * sin(dLon / 2);
  double c = 2 * atan2(sqrt(a), sqrt(1 - a));
  return R * c;
}

void comprobarReinicioPorGPS() {
  if (millis() - ultimoFixValido > MAX_SIN_FIX) {
    Serial.println("Reinicio: más de 20 min sin fix GPS válido");
    delay(1000);
    esp_restart();
  }
}

// ------------------------------------------------------------
// SETUP
// ------------------------------------------------------------
void setup() {
  Serial.begin(115200);
  modemSerial.begin(115200, SERIAL_8N1, MODEM_RX, MODEM_TX);
  powerOnModem();
  delay(2000);
  sendAT("AT+CGNSSPWR=1"); // Encender GNSS
  setup_wifi();
  client.setServer(mqtt_server, mqtt_port);

  lastCheck = millis();
  lastPublish = millis();
}

// ------------------------------------------------------------
// LOOP
// ------------------------------------------------------------
void loop() {
  client.loop();
  unsigned long now = millis();

  if (now - lastCheck > 30000UL) {
    lastCheck = now;

    sendAT("AT+CGNSSPWR=1", "OK", 2000);
    String raw = sendAT("AT+CGNSSINFO", "OK", 5000);

    // Extraer los datos GNSS
    int idx = raw.indexOf("+CGNSSINFO:");
    if (idx == -1) {
      Serial.println("No se encontró etiqueta +CGNSSINFO");
      comprobarReinicioPorGPS();
      return;
    }

    String data = raw.substring(idx + 12);
    data.trim();

    Serial.println("\n📡 Datos GNSS:");
    Serial.println(data);

    // Parseo manual de campos
    String fields[20];
    int pos = 0, fieldCount = 0;
    while (pos >= 0 && fieldCount < 18) {
      int comma = data.indexOf(',', pos);
      if (comma == -1) {
        fields[fieldCount++] = data.substring(pos);
        break;
      }
      fields[fieldCount++] = data.substring(pos, comma);
      pos = comma + 1;
    }

    // Si no hay fix válido
    if (fields[5] == "") {
      Serial.println("Sin fix GPS válido aún");
      comprobarReinicioPorGPS();
      return;
    }

    // Extraer datos
    String lat = fields[5];
    String latDir = fields[6];
    String lon = fields[7];
    String lonDir = fields[8];
    String alt = fields[11];
    String fechaHora = fields[10];
    float hdop = fields[15].toFloat();

    String hora = fechaHora.substring(0, 2) + ":" + fechaHora.substring(2, 4) + ":" + fechaHora.substring(4, 6);
    lastHdop = hdop;

    double currLat = lat.toFloat();
    if (latDir == "S") currLat *= -1;
    double currLng = lon.toFloat();
    if (lonDir == "W") currLng *= -1;

    double dist = calcularDistancia(lastLat, lastLng, currLat, currLng);
    bool ahoraMoviendo = dist > 30.0;

    Serial.println("GPS Fix válido");
    Serial.println("Lat: " + lat + " " + latDir);
    Serial.println("Lon: " + lon + " " + lonDir);
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
      if (!enMovimiento) lastPublish = now;
    }

    String csv = generarCSV(hora, String(currLat, 8), String(currLng, 8), alt, String(hdop, 1));
    String payload = cifrarCSV(csv);

    if ((enMovimiento && now - lastPublish > 40000UL && hdop <= 5.5 && payload != lastPayload) ||
        (!enMovimiento && now - lastPublish > 1800000UL)) {
      lastPublish = now;
      lastPayload = payload;
      publicar(payload);
    }
  }
}
