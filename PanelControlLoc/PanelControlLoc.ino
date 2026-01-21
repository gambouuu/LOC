#include <WiFi.h>
#include <PubSubClient.h>
#include <Wire.h>
#include <Adafruit_GFX.h>
#include <Adafruit_SSD1306.h>
#include <base64.h> // IMPORTANTE: misma lib que usas para el publicador
#include "mbedtls/base64.h"

// --- CONFIGURACIÓN WIFI & MQTT ---
const char* ssid = "XTA_75936";
const char* password = "3FMCvNVj";
const char* mqtt_server = "2.57.108.44";

WiFiClient espClient;
PubSubClient client(espClient);

// --- LEDS (asignación por usuario) ---
#define LED_jG       12
#define LED_PM       13
#define LED_Furgoubi 14
#define LED_Nomada   27

// --- DISPLAY OLED ---
#define SCREEN_WIDTH 128
#define SCREEN_HEIGHT 64
Adafruit_SSD1306 display(SCREEN_WIDTH, SCREEN_HEIGHT, &Wire, -1);

// --- ESTRUCTURAS ---
struct Usuario {
  String nombre;
  int pin;
  unsigned long ultimaPublicacion; // millis() del último mensaje válido
  bool estadoParpadeo;
};

Usuario usuarios[] = {
  {"jG",       LED_jG,       0, false},
  {"PM",       LED_PM,       0, false},
  {"Furgoubi", LED_Furgoubi, 0, false},
  {"Nomada",   LED_Nomada,   0, false}
};

unsigned long lastDisplayUpdate = 0;
unsigned long lastBlinkToggle   = 0;
const unsigned long blinkPeriod = 500; // ms, velocidad del parpadeo

// --- HELPERS ---
#include "mbedtls/base64.h"

String descifrarCSV(const String& b64) {
  // 1️⃣ Decodificar base64 usando mbedtls
  size_t out_len = 0;
  unsigned char out[256];  // tamaño suficiente para tu payload (~<200 bytes)
  int ret = mbedtls_base64_decode(out, sizeof(out), &out_len,
                                  (const unsigned char*)b64.c_str(), b64.length());
  if (ret != 0) {
    Serial.println("⚠️ Error decodificando Base64");
    return "";
  }

  // 2️⃣ Convertir a String
  String cifrado;
  for (size_t i = 0; i < out_len; i++) cifrado += (char)out[i];

  // 3️⃣ XOR con la misma clave que usa el tracker
  const String clave = "qu333yy-";
  String plano;
  plano.reserve(cifrado.length());
  for (int i = 0; i < cifrado.length(); i++) {
    char c = cifrado[i] ^ clave[i % clave.length()];
    plano += c;
  }

  return plano;  // Ejemplo: "jG,12:34:56,37.123456,-3.987654,650,1.2,1"
}


int indiceUsuario(const String& nombre) {
  for (int i = 0; i < (int)(sizeof(usuarios)/sizeof(usuarios[0])); i++) {
    if (usuarios[i].nombre == nombre) return i;
  }
  return -1;
}

void marcarActividad(const String& usuario) {
  int idx = indiceUsuario(usuario);
  if (idx >= 0) {
    usuarios[idx].ultimaPublicacion = millis();
    Serial.println("📡 Mensaje válido de: " + usuarios[idx].nombre);
  } else {
    Serial.println("ℹ️ Usuario no mapeado en panel: " + usuario);
  }
}

// --- WIFI / MQTT ---
void setup_wifi() {
  Serial.print("Conectando a WiFi...");
  WiFi.begin(ssid, password);
  while (WiFi.status() != WL_CONNECTED) {
    delay(1000); Serial.print(".");
  }
  Serial.println("\n✅ WiFi conectado");
}

void reconnect() {
  while (!client.connected()) {
    Serial.print("Conectando a MQTT...");
    // Usa aquí las credenciales que CREASTE para el panel
    if (client.connect("PanelControl", "PanelControl", "macarrones")) {
      Serial.println("✅ Conectado a MQTT");
      client.subscribe("ubi/campers");
    } else {
      Serial.print("❌ Fallo MQTT, rc=");
      Serial.print(client.state());
      Serial.println(" — Reintentando en 5s");
      delay(5000);
    }
  }
}

// --- CALLBACK MQTT ---
void callback(char* topic, byte* payload, unsigned int length) {
  // 1) payload → String base64
  String b64; b64.reserve(length);
  for (unsigned int i = 0; i < length; i++) b64 += (char)payload[i];

  // 2) Decodificar y descifrar a CSV
  String csv = descifrarCSV(b64);

  // Debug
  Serial.println("🔓 CSV: " + csv);

  // 3) Extraer primer campo (usuario)
  int coma = csv.indexOf(',');
  if (coma <= 0) {
    Serial.println("⚠️ CSV inválido (sin coma inicial): " + csv);
    return;
  }
  String usuario = csv.substring(0, coma);

  // 4) Marcar actividad para el usuario
  marcarActividad(usuario);
}

// --- LÓGICA LEDS / DISPLAY ---
void actualizarLeds() {
  unsigned long ahora = millis();

  // Manejar parpadeo con periodo fijo para todos
  if (ahora - lastBlinkToggle >= blinkPeriod) {
    lastBlinkToggle = ahora;
    for (auto &u : usuarios) {
      // Solo alternamos flag; el encendido real se decide más abajo
      u.estadoParpadeo = !u.estadoParpadeo;
    }
  }

  for (auto &u : usuarios) {
    // Si nunca recibió, apagar
    if (u.ultimaPublicacion == 0) {
      digitalWrite(u.pin, LOW);
      continue;
    }
    unsigned long diff = (ahora - u.ultimaPublicacion) / 1000; // en segundos

    if (diff < 180) { // < 3 min → encendido fijo
      digitalWrite(u.pin, HIGH);
    } else if (diff < 1800) { // 3–30 min → parpadeo
      digitalWrite(u.pin, u.estadoParpadeo ? HIGH : LOW);
    } else { // > 30 min → apagado
      digitalWrite(u.pin, LOW);
    }
  }
}

void actualizarPantalla() {
  display.clearDisplay();
  display.setTextSize(1);
  display.setTextColor(SSD1306_WHITE);
  display.setCursor(0, 0);
  display.println("PANEL DE CONTROL");

  unsigned long ahora = millis();
  for (int i = 0; i < 4; i++) {
    display.setCursor(0, 15 + i * 12);
    unsigned long diff = (usuarios[i].ultimaPublicacion == 0) ?
                         0 : (ahora - usuarios[i].ultimaPublicacion) / 1000;

    display.print(usuarios[i].nombre + ": ");
    if (usuarios[i].ultimaPublicacion == 0) {
      display.print("-");
    } else if (diff < 180) {
      display.print("Activo");
    } else if (diff < 1800) {
      display.print(String(diff / 60) + "m sin datos");
    } else {
      display.print("Inactivo");
    }
  }
  display.display();
}

// --- SETUP / LOOP ---
void setup() {
  Serial.begin(115200);

  // LEDs
  for (auto &u : usuarios) {
    pinMode(u.pin, OUTPUT);
    digitalWrite(u.pin, LOW);
  }

  // WiFi + MQTT
  setup_wifi();
  client.setServer(mqtt_server, 1883);
  client.setCallback(callback);

  // Buffer MQTT por si acaso (payload base64 no es grande, pero mejor dejar margen)
  client.setBufferSize(512);

  // Display I2C
  Wire.begin(21, 22);
  if (!display.begin(SSD1306_SWITCHCAPVCC, 0x3C)) {
    Serial.println("❌ No se detecta pantalla OLED (0x3C). Probando 0x3D...");
    if (!display.begin(SSD1306_SWITCHCAPVCC, 0x3D)) {
      Serial.println("❌ Tampoco 0x3D. Revisa SDA=21, SCL=22, VCC, GND.");
    }
  }
  display.clearDisplay();
  display.display();
}

void loop() {
  if (!client.connected()) reconnect();
  client.loop();

  actualizarLeds();

  if (millis() - lastDisplayUpdate > 2000) {
    lastDisplayUpdate = millis();
    actualizarPantalla();
  }

  delay(20);
}
