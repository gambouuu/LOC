import base64
import time
from datetime import datetime
import paho.mqtt.client as mqtt

MQTT_BROKER = "IPSERVER"
MQTT_PORT = PORT
MQTT_TOPIC = "ubi/campers"
MQTT_USER = "USER"
MQTT_PASS = "PASSWD"

CLAVE_XOR = "CLAVE"

def cifrar_csv(csv, clave=CLAVE_XOR):
    cifrado = ''.join(chr(ord(c) ^ ord(clave[i % len(clave)])) for i, c in enumerate(csv))
    return base64.b64encode(cifrado.encode()).decode()

def generar_csv(nombre, lat, lon):
    hora_utc = datetime.utcnow().strftime("%H:%M:%S")
    alt = 100.0  # valor ficticio
    hdop = 1.2   # valor válido
    en_mov = 1   # movimiento detectado
    return f"{nombre},{hora_utc},{lat},{lon},{alt},{hdop},{en_mov}"

if __name__ == "__main__":
    client = mqtt.Client()
    client.username_pw_set(MQTT_USER, MQTT_PASS)
    print(f"Conectando a {MQTT_BROKER}:{MQTT_PORT} como {MQTT_USER}...")
    client.connect(MQTT_BROKER, MQTT_PORT, 60)
    client.loop_start()

    nombre_usuario = "Nomada"
    ubicaciones = [
        (40.4168, -3.7038), 
        (40.4170, -3.7036),  
        (40.4172, -3.7034), 
    ]

    for i, (lat, lon) in enumerate(ubicaciones):
        csv = generar_csv(nombre_usuario, lat, lon)
        cifrado_b64 = cifrar_csv(csv)
        client.publish(MQTT_TOPIC, cifrado_b64)
        print(f"Enviado registro {i+1}: {csv}")
        if i < len(ubicaciones) - 1:
            time.sleep(20)  

    client.loop_stop()
    client.disconnect()
    print("Script finalizado.")
