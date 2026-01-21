import psycopg2
from passlib.hash import bcrypt

# Configuración de conexión
POSTGRES_CONFIG = {
    "host": "IPHOST",
    "port": PUERTO,
    "user": "USERNAME",
    "password": "PASSWORD", 
    "database": "DBNAME"
}

def cambiar_contraseña(nombre_usuario, nueva_contraseña):
    # Hashear la nueva contraseña
    contraseña_hash = bcrypt.hash(nueva_contraseña)

    # Conectar a la base de datos
    conn = psycopg2.connect(**POSTGRES_CONFIG)
    cur = conn.cursor()

    try:
        # Ejecutar el UPDATE
        cur.execute("""
            UPDATE usuarios
            SET contraseña = %s
            WHERE nombre = %s
        """, (contraseña_hash, nombre_usuario))
        conn.commit()

        if cur.rowcount == 0:
            print("Usuario no encontrado.")
        else:
            print("Contraseña actualizada correctamente.")
    except Exception as e:
        conn.rollback()
        print(f"Error al actualizar: {e}")
    finally:
        conn.close()

# Ejemplo de uso
cambiar_contraseña("USER", "PASSWORD")
