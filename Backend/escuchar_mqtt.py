import base64
import paho.mqtt.client as mqtt

# Configuración del broker
MQTT_BROKER = "IP_SERVER"
MQTT_PORT = PUERTO
MQTT_TOPIC = "ubi/campers"

CLAVE_XOR = "CLAVE"

def descifrar_csv(b64_encoded, clave=CLAVE_XOR):
    try:
        cifrado = base64.b64decode(b64_encoded).decode()
        plano = ''.join(chr(ord(c) ^ ord(clave[i % len(clave)])) for i, c in enumerate(cifrado))
        return plano
    except Exception as e:
        return f"[ERROR DESCIFRANDO] {e}"

def on_connect(client, userdata, flags, rc):
    print("Conectado al broker MQTT. Código de estado:", rc)
    client.subscribe(MQTT_TOPIC)

def on_message(client, userdata, msg):
    print(f"\nMensaje recibido en '{msg.topic}'")
    b64_payload = msg.payload.decode()
    csv = descifrar_csv(b64_payload)
    print("Mensaje descifrado:", csv)

# Inicializar cliente MQTT
client = mqtt.Client()
client.on_connect = on_connect
client.on_message = on_message

print(f"Conectando a {MQTT_BROKER}:{MQTT_PORT}...")
client.connect(MQTT_BROKER, MQTT_PORT, 60)
client.loop_forever()
