import base64
import psycopg2
import paho.mqtt.client as mqtt
import time
from datetime import datetime
from google.oauth2 import service_account
import google.auth.transport.requests
import requests


# Configuración del broker
MQTT_BROKER = "IP_SERVER"
MQTT_PORT = PORT
MQTT_TOPIC = "ubi/campers"
MQTT_USER = "USER"
MQTT_PASS = "PASSWD"
SERVICE_ACCOUNT_FILE = '/mnt/disk2/../../../api/loc_acc_file/xxx.json'
PROJECT_ID = 'ID'

# Clave de cifrado usada en el ESP32
CLAVE_XOR = "CLAVE"

# =======================
# CONEXIÓN A POSTGRESQL
# =======================
def get_pg_conn():
    return psycopg2.connect(
        host="SERVERIP",
        port=PORT,
        dbname="DBNAME",
        user="DBUSER",
        password="PASSWD"
    )

# =======================
# FUNCIONES AUXILIARES
# =======================
def descifrar_csv(b64_encoded, clave=CLAVE_XOR):
    try:
        cifrado = base64.b64decode(b64_encoded).decode()
        plano = ''.join(chr(ord(c) ^ ord(clave[i % len(clave)])) for i, c in enumerate(cifrado))
        return plano
    except Exception as e:
        return f"[ERROR DESCIFRANDO] {e}"

def insertar_datos(csv):
    campos = csv.split(',')
    if len(campos) != 7:
        print("CSV mal formado, se esperaban 7 campos:", campos)
        return

    nombre_usuario, hora_utc, lat, lon, alt, hdop, en_mov = campos

    try:
        lat, lon = float(lat), float(lon)
        alt, hdop = float(alt), float(hdop)
        en_mov = int(en_mov)
    except ValueError:
        print("Error de conversión de tipos en los campos numéricos.")
        return

    conn = get_pg_conn()
    cursor = conn.cursor()

    # Verificar si el usuario existe
    cursor.execute("SELECT id FROM usuarios WHERE nombre = %s", (nombre_usuario,))
    fila = cursor.fetchone()

    if fila:
        usuario_id = fila[0]
    else:
        cursor.execute("INSERT INTO usuarios (nombre, contraseña, correo) VALUES (%s, %s, %s) RETURNING id",
                       (nombre_usuario, "default", "sin@email.com"))
        usuario_id = cursor.fetchone()[0]

    # Insertar el nuevo registro
    cursor.execute('''
        INSERT INTO ubicaciones (usuario_id, hora_utc, latitud, longitud, altitud, hdop, en_movimiento, recibido_en)
        VALUES (%s, %s, %s, %s, %s, %s, %s, NOW())
    ''', (usuario_id, hora_utc, lat, lon, alt, hdop, en_mov))
    conn.commit()

    print(f"Datos insertados para usuario '{nombre_usuario}'.", flush=True)

    # Evaluar últimos 3 registros para detección automática
    cursor.execute("""
        SELECT hora_utc, en_movimiento, hdop FROM ubicaciones 
        WHERE usuario_id = %s
        ORDER BY recibido_en DESC LIMIT 3
    """, (usuario_id,))
    ultimos_3 = cursor.fetchall()

    if (
        len(ultimos_3) == 3 and
        all(r[1] == 1 and r[2] is not None and r[2] < 5.5 for r in ultimos_3)
    ):
        try:
            h1 = datetime.strptime(ultimos_3[0][0], "%H:%M:%S")
            h3 = datetime.strptime(ultimos_3[2][0], "%H:%M:%S")
            if abs((h1 - h3).total_seconds()) <= 180:
                print(f"Movimiento detectado para usuario {nombre_usuario}", flush=True)

                # Verificar último estado registrado para evitar notificaciones duplicadas
                cursor.execute("""
                    SELECT en_movimiento FROM ubicaciones
                    WHERE usuario_id = %s
                    ORDER BY recibido_en DESC OFFSET 3 LIMIT 1
                """, (usuario_id,))
                ultimo_estado = cursor.fetchone()
                if ultimo_estado and ultimo_estado[0] == 1:
                    print("Ya había movimiento antes, no se envía notificación repetida.", flush=True)
                else:
                    # Obtener token FCM del usuario
                    cursor.execute("SELECT fcm_token FROM usuarios WHERE id = %s", (usuario_id,))
                    fcm = cursor.fetchone()
                    fcm_token = fcm[0] if fcm and fcm[0] else None

                    if fcm_token:
                        enviar_notificacion_fcm_v1(
                            fcm_token,
                            "Alerta de movimiento",
                            "Se detectó movimiento en tu vehículo, por favor revísalo."
                        )
                    else:
                        print("No hay token FCM registrado para este usuario.", flush=True)
        except Exception as e:
            print(f"Error evaluando movimiento: {e}", flush=True)

    cursor.close()
    conn.close()

def enviar_notificacion_fcm_v1(token_fcm, titulo, cuerpo):
    try:
        credentials = service_account.Credentials.from_service_account_file(
            SERVICE_ACCOUNT_FILE,
            scopes=['https://www.googleapis.com/auth/firebase.messaging']
        )

        request = google.auth.transport.requests.Request()
        credentials.refresh(request)
        access_token = credentials.token

        message = {
            "message": {
                "token": token_fcm,
                "notification": {
                    "title": titulo,
                    "body": cuerpo
                }
            }
        }

        url = f"https://fcm.googleapis.com/v1/projects/{PROJECT_ID}/messages:send"
        headers = {
            'Authorization': f'Bearer {access_token}',
            'Content-Type': 'application/json; UTF-8',
        }

        response = requests.post(url, headers=headers, json=message)
        print(f"FCM Notificación enviada", flush=True)
    except Exception as e:
        print(f"Error enviando notificación FCM: {e}", flush=True)


# =======================
# FUNCIONES MQTT
# =======================
def on_connect(client, userdata, flags, rc):
    print("Conectado al broker MQTT. Código de estado:", rc, flush=True)
    client.subscribe(MQTT_TOPIC)

def on_message(client, userdata, msg):
    print(f"\nMensaje recibido en '{msg.topic}'", flush=True)
    b64_payload = msg.payload.decode()
    csv = descifrar_csv(b64_payload)
    print("CSV descifrado:", csv, flush=True)

    if not csv.startswith("[ERROR"):
        for intento in range(3):
            try:
                insertar_datos(csv)
                break
            except psycopg2.OperationalError as e:
                print("PostgreSQL ocupado, reintentando...", flush=True)
                time.sleep(0.3)
            except Exception as e:
                print("Error al insertar en PostgreSQL:", e, flush=True)
                break
    else:
        print(csv)

# =======================
# MAIN
# =======================
if __name__ == "__main__":
    client = mqtt.Client()
    client.username_pw_set(MQTT_USER, MQTT_PASS)
    client.on_connect = on_connect
    client.on_message = on_message

    print(f"🔌 Conectando a {MQTT_BROKER}:{MQTT_PORT} como {MQTT_USER}...", flush=True)
    client.connect(MQTT_BROKER, MQTT_PORT, 60)
    client.loop_forever()
