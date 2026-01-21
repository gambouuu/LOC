# utils/enviar_correo.py
import random
import smtplib
from email.mime.text import MIMEText
from email.mime.multipart import MIMEMultipart
from datetime import datetime
import os
import psycopg2

SMTP_USER = "mail@mail.com"
SMTP_PASS = "PASSWD"
SMTP_SERVER = "SERVER"
SMTP_PORT = SMTP_PORT

# Parámetros de PostgreSQL
PG_DB = "DB"
PG_USER = "USERNAME"
PG_PASSWORD = "PSW"
PG_HOST = "IPHOST"
PG_PORT = "PUERTO"

# === FUNCIONES ===

def guardar_codigo_en_db(email: str, codigo: str, usuario: str):
    ahora = datetime.utcnow().isoformat()

    conn = psycopg2.connect(
        dbname=PG_DB,
        user=PG_USER,
        password=PG_PASSWORD,
        host=PG_HOST,
        port=PG_PORT
    )
    cur = conn.cursor()

    cur.execute('''
        CREATE TABLE IF NOT EXISTS codigos_verificacion (
            email TEXT PRIMARY KEY,
            usuario TEXT NOT NULL,
            codigo TEXT NOT NULL,
            generado_en TEXT NOT NULL
        );
    ''')

    cur.execute("""
        INSERT INTO codigos_verificacion (email, usuario, codigo, generado_en)
        VALUES (%s, %s, %s, %s)
        ON CONFLICT (email) DO UPDATE SET
            usuario = EXCLUDED.usuario,
            codigo = EXCLUDED.codigo,
            generado_en = EXCLUDED.generado_en
    """, (email, usuario, codigo, ahora))

    conn.commit()
    conn.close()



def enviar_codigo_verificacion(destinatario: str, codigo: str, usuario: str):
    asunto = "Bienvenido a Nomada - Aquí está tu código de acceso"

    html = f"""
    <html>
    <body style="font-family: Arial, sans-serif; background-color: #f9f9f9; padding: 20px;">
        <div style="max-width: 600px; margin: auto; background-color: #ffffff; padding: 30px; border-radius: 10px; box-shadow: 0 2px 5px rgba(0,0,0,0.1);">

        <h1 style="color: #2c3e50; text-align: center;">👋 Bienvenido a Nomada</h1>

        <p style="font-size: 16px; color: #333;">Gracias por comprar un localizador en <strong>Nómada</strong>, tu asistente inteligente para localizar y proteger tu camper o autocaravana.</p>

        <p style="font-size: 16px; color: #333;">Tu <strong>código de verificación</strong> es:</p>

        <div style="text-align: center; margin: 20px 0;">
            <span style="font-size: 36px; letter-spacing: 6px; font-weight: bold; color: #2980b9;">{codigo}</span>
        </div>

        <p style="font-size: 16px; color: #333;">Tu <strong>nombre de usuario asignado</strong> es:</p>

        <div style="text-align: center; margin: 20px 0;">
            <span style="font-size: 28px; letter-spacing: 2px; font-weight: bold; color: #16a085;">{usuario}</span>
        </div>

        <p style="font-size: 16px; color: #333;">Si tú no solicitaste esta verificación, puedes ignorar este mensaje sin problema.</p>

        <hr style="margin: 40px 0; border: none; border-top: 1px solid #ddd;" />

        <p style="font-size: 12px; color: #999;">
            Este mensaje ha sido enviado automáticamente por el equipo de <strong>Nomada</strong> creado por <strong>Marc Gamboa</strong>.<br />
            Si tienes preguntas o necesitas ayuda, contáctanos respondiendo a este correo.
        </p>
        </div>
    </body>
    </html>
    """

    msg = MIMEMultipart("related")
    msg["Subject"] = asunto
    msg["From"] = SMTP_USER
    msg["To"] = destinatario

    msg_alt = MIMEMultipart("alternative")
    msg.attach(msg_alt)
    msg_alt.attach(MIMEText(html, "html"))

    try:
        with smtplib.SMTP(SMTP_SERVER, SMTP_PORT) as server:
            server.starttls()
            server.login(SMTP_USER, SMTP_PASS)
            server.send_message(msg)
            print(f"Código enviado a {destinatario}")
    except Exception as e:
        print(f"Error al enviar correo: {e}")

# === EJECUCIÓN MANUAL ===
if __name__ == "__main__":
    destino = "mail@gmail.com"
    usuario = "XXXX" 
    codigo = str(random.randint(0, 999999)).zfill(6)
    print(f"Código generado para {usuario}: {codigo}")
    guardar_codigo_en_db(destino, codigo, usuario)
    enviar_codigo_verificacion(destino, codigo, usuario)
