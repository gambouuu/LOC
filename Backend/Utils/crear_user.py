from passlib.hash import bcrypt
import sqlite3

conn = sqlite3.connect("datos_mqtt.db")
cur = conn.cursor()
nombre = "USERNAME"
contraseña = bcrypt.hash("PASSWD")
cur.execute("DELETE FROM usuarios WHERE nombre = ?", (nombre,))
cur.execute("INSERT INTO usuarios (nombre, contraseña, correo) VALUES (?, ?, ?)", (nombre, contraseña, "mail@mail.com"))
conn.commit()
conn.close()
