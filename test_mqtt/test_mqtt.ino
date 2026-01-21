#include <HardwareSerial.h>

HardwareSerial modemSerial(1);

#define MODEM_RX 16
#define MODEM_TX 17
#define MODEM_PWRKEY 4

const char* mqtt_broker_ip = "2.57.108.44";
const char* mqtt_topic = "ubi/campers";

void powerOnModem() {
  pinMode(MODEM_PWRKEY, OUTPUT);
  digitalWrite(MODEM_PWRKEY, LOW);
  delay(1000);
  digitalWrite(MODEM_PWRKEY, HIGH);
  delay(1000);
  digitalWrite(MODEM_PWRKEY, LOW);
  delay(10000);
}

bool sendAT(String cmd, String expected = "OK", int timeout = 8000) {
  Serial.println(">> " + cmd);
  modemSerial.println(cmd);
  String resp = "";
  unsigned long start = millis();

  while (millis() - start < timeout) {
    while (modemSerial.available()) {
      char c = modemSerial.read();
      resp += c;
      Serial.write(c);
      if (resp.indexOf(expected) != -1) return true;
    }
  }

  Serial.println("❌ No se obtuvo respuesta esperada");
  return false;
}

bool waitForCREG() {
  for (int i = 0; i < 10; i++) {
    if (sendAT("AT+CREG?", "+CREG: 0,1") || sendAT("AT+CREG?", "+CREG: 0,5"))
      return true;
    delay(3000);
  }
  return false;
}

bool conectarRed() {
  sendAT("AT+CFUN=0", "OK", 5000);
  delay(3000);
  sendAT("AT+CGDCONT=1,\"IP\",\"comgate.m2m\"");
  // Algunos módulos no requieren autenticación, se omite si falla
  sendAT("AT+CGAUTH=1,1,\"davantel\",\"davantel\"");
  sendAT("AT+CFUN=1", "OK", 5000);
  delay(5000);
  sendAT("AT+COPS=0", "OK", 10000);
  return waitForCREG() && sendAT("AT+CGATT=1");
}

bool iniciarMQTT() {
  sendAT("AT+CMQTTSTOP", "OK", 3000);
  delay(500);
  if (!sendAT("AT+CMQTTSTART")) return false;
  delay(500);
  if (!sendAT("AT+CMQTTACCQ=0,\"ESP32TEST\"")) return false;

  return sendAT("AT+CMQTTCONNECT=0,\"tcp://" + String(mqtt_broker_ip) + ":1883\",60,1,\"camper\",\"gamboalocalizador\"", "OK", 10000);
}

bool publicarMQTT(String payload) {
  if (!sendAT("AT+CMQTTTOPIC=0," + String(strlen(mqtt_topic)), ">", 3000)) return false;
  modemSerial.print(mqtt_topic);
  delay(300);

  if (!sendAT("AT+CMQTTPAYLOAD=0," + String(payload.length()), ">", 3000)) return false;
  modemSerial.print(payload);
  delay(300);

  return sendAT("AT+CMQTTPUB=0,1,60", "+CMQTTPUB: 0,0", 5000);
}

void setup() {
  Serial.begin(115200);
  modemSerial.begin(115200, SERIAL_8N1, MODEM_RX, MODEM_TX);
  delay(1000);

  powerOnModem();
  delay(2000);

  if (!sendAT("AT") || !sendAT("AT+CPIN?", "+CPIN: READY")) {
    Serial.println("❌ Error: SIM no lista");
    return;
  }

  if (conectarRed()) {
    Serial.println("✅ Conectado a la red móvil");

    if (iniciarMQTT()) {
      Serial.println("📡 MQTT iniciado correctamente");

      if (publicarMQTT("Mensaje de prueba desde ESP32")) {
        Serial.println("✅ Mensaje MQTT publicado");
      } else {
        Serial.println("❌ Fallo al publicar");
      }

      sendAT("AT+CMQTTDISC=0,60");
      sendAT("AT+CMQTTREL=0");
      sendAT("AT+CMQTTSTOP");
    } else {
      Serial.println("❌ Fallo al iniciar MQTT");
    }
  } else {
    Serial.println("❌ No se pudo conectar a red móvil");
  }
}

void loop() {}
