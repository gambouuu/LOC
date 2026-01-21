# main_postgres.py
from fastapi import FastAPI, HTTPException, Depends, Form, Security, Body
from fastapi.middleware.cors import CORSMiddleware
from fastapi.security import OAuth2PasswordBearer
from pydantic import BaseModel
from typing import List
from math import radians, cos, sin, asin, sqrt
import psycopg2
import psycopg2.extras
from passlib.hash import bcrypt
from datetime import datetime, timedelta
from jose import jwt, JWTError

app = FastAPI()

app.add_middleware(
    CORS_CONFIG
)

POSTGRES_CONFIG = {
    "host": "IPHOST",
    "port": PUERTO,
    "user": "USERNAME",
    "password": "PASSWORD", 
    "database": "DBNAME"
}

SECRET_KEY = "SECRETKEY"
ALGORITHM = "ALGORITHM"
ACCESS_TOKEN_EXPIRE_MINUTES = 60 * 24 * 14

oauth2_scheme = OAuth2PasswordBearer(tokenUrl="/token")

# --------------------------
# Utilidades
# --------------------------
def get_db():
    conn = psycopg2.connect(**POSTGRES_CONFIG)
    return conn

def crear_token_acceso(data: dict, expires_delta: timedelta = None):
    to_encode = data.copy()
    expire = datetime.utcnow() + (expires_delta or timedelta(minutes=ACCESS_TOKEN_EXPIRE_MINUTES))
    to_encode.update({"exp": expire})
    return jwt.encode(to_encode, SECRET_KEY, algorithm=ALGORITHM)

def verificar_token(token: str = Security(oauth2_scheme)):
    try:
        payload = jwt.decode(token, SECRET_KEY, algorithms=[ALGORITHM])
        return payload
    except JWTError:
        raise HTTPException(status_code=401, detail="Token inválido o expirado")
    
def formatear_fecha(fecha: datetime):
    ahora = datetime.utcnow()
    if fecha.tzinfo is not None:
        fecha = fecha.astimezone(tz=None).replace(tzinfo=None)
    delta = ahora - fecha

    if delta > timedelta(days=7):
        return "> 1 semana"
    elif delta > timedelta(days=1):
        return "> 1 día"
    else:
        return fecha.strftime("%H:%M:%S")
    
def haversine(lat1, lon1, lat2, lon2):
    R = 6371.0  # Radio de la Tierra en km
    dlat = radians(lat2 - lat1)
    dlon = radians(lon2 - lon1)
    a = sin(dlat/2)**2 + cos(radians(lat1)) * cos(radians(lat2)) * sin(dlon/2)**2
    return 2 * R * asin(sqrt(a))

def calcular_distancia(conn, usuario_id: int, dias: int):
    cur = conn.cursor()
    fecha_inicio = (datetime.utcnow() - timedelta(days=dias)).strftime('%Y-%m-%d %H:%M:%S')
    cur.execute('''
        SELECT latitud, longitud
        FROM ubicaciones
        WHERE usuario_id = %s AND recibido_en >= %s
        ORDER BY recibido_en ASC
    ''', (usuario_id, fecha_inicio))

    puntos = cur.fetchall()
    total = 0.0
    for i in range(1, len(puntos)):
        lat1, lon1 = puntos[i - 1]
        lat2, lon2 = puntos[i]
        total += haversine(lat1, lon1, lat2, lon2)

    return round(total, 2)

# --------------------------
# Modelos
# --------------------------
class Ubicacion(BaseModel):
    hora_utc: str
    latitud: float
    longitud: float
    altitud: float | None = None
    hdop: float | None = None
    en_movimiento: int
    recibido_en: str

class TokenFCM(BaseModel):
    fcm_token: str

# --------------------------
# Endpoints
# --------------------------
@app.post("/token")
def login_token(nombre: str = Form(...), contraseña: str = Form(...)):
    conn = get_db()
    cur = conn.cursor(cursor_factory=psycopg2.extras.RealDictCursor)
    cur.execute("SELECT * FROM usuarios WHERE nombre = %s", (nombre,))
    user = cur.fetchone()
    conn.close()

    if not user or not bcrypt.verify(contraseña, user["contraseña"]):
        raise HTTPException(status_code=401, detail="Credenciales inválidas")

    token = crear_token_acceso({"sub": str(user["id"])})
    return {"access_token": token, "token_type": "bearer"}

@app.post("/registrar_token")
def registrar_token(
    token_data: TokenFCM,
    usuario: dict = Depends(verificar_token)
):
    usuario_id = int(usuario["sub"])
    fcm_token = token_data.fcm_token

    conn = get_db()
    cur = conn.cursor()
    cur.execute("""
        UPDATE usuarios SET fcm_token = %s WHERE id = %s
    """, (fcm_token, usuario_id))
    conn.commit()
    conn.close()
    return {"mensaje": "Token FCM registrado correctamente"}


@app.get("/estado_actual")
def estado_actual(usuario: dict = Depends(verificar_token)):
    usuario_id = int(usuario["sub"])
    conn = get_db()
    cur = conn.cursor(cursor_factory=psycopg2.extras.RealDictCursor)

    cur.execute("""
        SELECT * FROM ubicaciones 
        WHERE usuario_id = %s 
        ORDER BY recibido_en DESC LIMIT 1
    """, (usuario_id,))
    ultima = cur.fetchone()
    if not ultima:
        raise HTTPException(status_code=404, detail="No se encontró ubicación")

    # Evaluar estado actual (últimos 3 registros)
    cur.execute("""
        SELECT recibido_en, en_movimiento, hdop FROM ubicaciones 
        WHERE usuario_id = %s 
        ORDER BY recibido_en DESC LIMIT 3
    """, (usuario_id,))
    ultimos_3 = cur.fetchall()

    estado = "Reposo"
    if (
        len(ultimos_3) == 3 and
        all(r["en_movimiento"] == 1 and r["hdop"] is not None and r["hdop"] < 5.5 for r in ultimos_3)
    ):
        try:
            t1 = ultimos_3[0]["recibido_en"]
            t3 = ultimos_3[2]["recibido_en"]
            if abs((t1 - t3).total_seconds()) <= 180:
                estado = "Movimiento"
        except:
            pass

    # Buscar la última vez con movimiento válido
    cur.execute("""
        SELECT recibido_en, en_movimiento, hdop FROM ubicaciones 
        WHERE usuario_id = %s 
        ORDER BY recibido_en DESC LIMIT 50
    """, (usuario_id,))
    registros = cur.fetchall()

    ultima_vez_mov = None
    for i in range(len(registros) - 2):
        r1, r2, r3 = registros[i], registros[i+1], registros[i+2]
        if (
            r1["en_movimiento"] == 1 and r2["en_movimiento"] == 1 and r3["en_movimiento"] == 1 and
            all(r["hdop"] is not None and r["hdop"] < 5.5 for r in [r1, r2, r3])
        ):
            try:
                t1 = r1["recibido_en"]
                t3 = r3["recibido_en"]
                if abs((t1 - t3).total_seconds()) <= 180:
                    ultima_vez_mov = t1
                    break
            except:
                pass

    conn.close()

    return {
        "estado": estado,
        "ultima_actualizacion": formatear_fecha(ultima["recibido_en"]),
        "ultima_vez_en_movimiento": formatear_fecha(ultima_vez_mov) if ultima_vez_mov else "--:--:--"
    }

@app.get("/ubicacion_actual", response_model=Ubicacion)
def ubicacion_actual(usuario: dict = Depends(verificar_token)):
    usuario_id = int(usuario["sub"])
    conn = get_db()
    cur = conn.cursor(cursor_factory=psycopg2.extras.RealDictCursor)
    cur.execute("""
        SELECT * FROM ubicaciones 
        WHERE usuario_id = %s 
        ORDER BY recibido_en DESC LIMIT 1
    """, (usuario_id,))
    ubic = cur.fetchone()
    conn.close()

    if not ubic:
        raise HTTPException(status_code=404, detail="No se encontró ubicación")

    if isinstance(ubic["recibido_en"], datetime):
        ubic["recibido_en"] = ubic["recibido_en"].strftime("%Y-%m-%d %H:%M:%S")

    return dict(ubic)

@app.get("/ruta", response_model=List[Ubicacion])
def obtener_ruta(limite: int = 5000, usuario: dict = Depends(verificar_token)):
    usuario_id = int(usuario["sub"])
    conn = get_db()
    cur = conn.cursor(cursor_factory=psycopg2.extras.RealDictCursor)
    cur.execute("""
        SELECT * FROM ubicaciones 
        WHERE usuario_id = %s 
        ORDER BY recibido_en DESC LIMIT %s
    """, (usuario_id, limite))
    ubicaciones = cur.fetchall()
    conn.close()

    for ubic in ubicaciones:
        if isinstance(ubic["recibido_en"], datetime):
            ubic["recibido_en"] = ubic["recibido_en"].strftime("%Y-%m-%d %H:%M:%S")

    return ubicaciones

class RangoFechas(BaseModel):
    fecha_inicio: datetime
    fecha_fin: datetime

@app.post("/ruta/fechas", response_model=List[Ubicacion])
def obtener_ruta_por_fechas(
    rango: RangoFechas = Body(...),
    usuario: dict = Depends(verificar_token)
):
    usuario_id = int(usuario["sub"])
    conn = get_db()
    cur = conn.cursor(cursor_factory=psycopg2.extras.RealDictCursor)

    cur.execute("""
        SELECT * FROM ubicaciones
        WHERE usuario_id = %s
        AND recibido_en BETWEEN %s AND %s
        ORDER BY recibido_en ASC
    """, (usuario_id, rango.fecha_inicio, rango.fecha_fin))

    ubicaciones = cur.fetchall()
    conn.close()

    for ubic in ubicaciones:
        if isinstance(ubic["recibido_en"], datetime):
            ubic["recibido_en"] = ubic["recibido_en"].strftime("%Y-%m-%d %H:%M:%S")

    return ubicaciones

@app.get("/distancia_7_dias")
def distancia_7_dias(usuario: dict = Depends(verificar_token)):
    usuario_id = int(usuario["sub"])
    conn = get_db()
    distancia = calcular_distancia(conn, usuario_id, 7)
    conn.close()
    return {"km_recorridos": distancia, "dias": 7}

@app.get("/distancia_30_dias")
def distancia_30_dias(usuario: dict = Depends(verificar_token)):
    usuario_id = int(usuario["sub"])
    conn = get_db()
    distancia = calcular_distancia(conn, usuario_id, 30)
    conn.close()
    return {"km_recorridos": distancia, "dias": 30}

@app.post("/registrar")
def registrar(
    email: str = Form(...),
    nombre: str = Form(...),
    contraseña: str = Form(...),
    codigo: str = Form(...)
):
    conn = get_db()
    cur = conn.cursor(cursor_factory=psycopg2.extras.RealDictCursor)

    cur.execute("SELECT codigo, generado_en, usuario FROM codigos_verificacion WHERE email = %s", (email,))
    row = cur.fetchone()

    if not row:
        conn.close()
        raise HTTPException(status_code=400, detail="Correo no encontrado en la lista de verificación")

    if row["codigo"] != codigo:
        conn.close()
        raise HTTPException(status_code=400, detail="Código de verificación incorrecto")

    if row["usuario"] != nombre:
        conn.close()
        raise HTTPException(status_code=400, detail="El nombre de usuario no coincide con el asignado")

    # Hashear contraseña
    contraseña_hash = bcrypt.hash(contraseña)

    try:
        cur.execute(
            "INSERT INTO usuarios (nombre, contraseña, correo) VALUES (%s, %s, %s)",
            (nombre, contraseña_hash, email)
        )
        conn.commit()
    except psycopg2.IntegrityError:
        conn.rollback()
        conn.close()
        raise HTTPException(status_code=400, detail="El nombre o correo ya está registrado")

    # Eliminar el código usado
    cur.execute("DELETE FROM codigos_verificacion WHERE email = %s", (email,))
    conn.commit()
    conn.close()

    return {"mensaje": "Usuario registrado correctamente"}
