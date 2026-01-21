#include <HardwareSerial.h>

#define MODEM_RX 16
#define MODEM_TX 17
#define MODEM_PWRKEY 4

HardwareSerial modemSerial(1);

void enviarComando(String comando, int tiempo = 3000) {
  Serial.println("[CMD] " + comando);
  modemSerial.println(comando);
  unsigned long t0 = millis();
  while (millis() - t0 < tiempo) {
    while (modemSerial.available()) {
      char c = modemSerial.read();
      Serial.write(c);
    }
  }
  Serial.println();
}

void encenderModem() {
  Serial.println("[MODEM] Encendiendo módem...");
  pinMode(MODEM_PWRKEY, OUTPUT);
  digitalWrite(MODEM_PWRKEY, LOW);
  delay(1000);
  digitalWrite(MODEM_PWRKEY, HIGH);
  delay(1000);
  digitalWrite(MODEM_PWRKEY, LOW);
  delay(10000);
  Serial.println("[MODEM] Módem encendido");
}

void probarAPN(const char* nombre, const char* apn, const char* usuario = "", const char* clave = "") {
  Serial.println("\n== PROBANDO APN: " + String(nombre) + " ==");

  enviarComando("AT+CFUN=0", 3000);
  delay(3000);

  String cmd = "AT+CGDCONT=1,\"IP\",\"" + String(apn) + "\"";
  enviarComando(cmd);

  if (String(usuario).length() > 0)
    enviarComando("AT+CGAUTH=1,1,\"" + String(usuario) + "\",\"" + String(clave) + "\"");

  enviarComando("AT+CFUN=1", 3000);
  delay(3000);

  enviarComando("AT+COPS=0", 5000);
  delay(5000);

  for (int i = 0; i < 6; i++) {
    enviarComando("AT+CREG?", 2000);
    delay(3000);
  }

  enviarComando("AT+CGATT=1", 5000);
  delay(2000);
  enviarComando("AT+CGATT?", 2000);
  enviarComando("AT+CGPADDR=1", 2000);
}

void setup() {
  Serial.begin(115200);
  modemSerial.begin(115200, SERIAL_8N1, MODEM_RX, MODEM_TX);
  delay(1000);

  encenderModem();
  delay(2000);

  enviarComando("AT");
  enviarComando("AT+CPIN?");

  probarAPN("Davantel M2M", "comgate.m2m", "davantel", "davantel");
}

void loop() {}
