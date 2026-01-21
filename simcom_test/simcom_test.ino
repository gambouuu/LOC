#include <HardwareSerial.h>

#define MODEM_RX 16
#define MODEM_TX 17
#define MODEM_PWRKEY 4

HardwareSerial modemSerial(1);
bool encendido = false;

void powerOnModem() {
  if (encendido) return;
  pinMode(MODEM_PWRKEY, OUTPUT);
  digitalWrite(MODEM_PWRKEY, LOW);
  delay(2000);
  digitalWrite(MODEM_PWRKEY, HIGH);
  delay(100);
  digitalWrite(MODEM_PWRKEY, LOW);
  delay(10000);
  encendido = true;
}

void setup() {
  Serial.begin(115200);
  modemSerial.begin(115200, SERIAL_8N1, MODEM_RX, MODEM_TX);
  delay(500);
  powerOnModem();
  delay(1000);
  modemSerial.println("AT");
}

void loop() {
  while (modemSerial.available()) {
    Serial.write(modemSerial.read());
  }
}
