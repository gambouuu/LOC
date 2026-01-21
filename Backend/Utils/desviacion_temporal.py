import psycopg2
from statistics import mean, pstdev

POSTGRES_CONFIG = {
    "host": "IPHOST",
    "port": PUERTO,
    "user": "USERNAME",
    "password": "PASSWORD", 
    "database": "DBNAME"
}

TABLE_NAME = "ubicaciones"

QUERY = f"""
WITH last1000 AS (
  SELECT
    id,
    hora_utc,
    recibido_en,
    (EXTRACT(MINUTE FROM recibido_en)::int * 60 +
     EXTRACT(SECOND FROM recibido_en)::int) AS rec_mmss_s,
    (EXTRACT(MINUTE FROM CAST(hora_utc AS time))::int * 60 +
     EXTRACT(SECOND FROM CAST(hora_utc AS time))::int) AS utc_mmss_s
  FROM {TABLE_NAME}
  ORDER BY id DESC
  LIMIT 400
)
SELECT
  id,
  hora_utc,
  recibido_en,
  (utc_mmss_s - rec_mmss_s) AS diff_raw_s,
  (((utc_mmss_s - rec_mmss_s + 1800) % 3600) - 1800) AS diff_circular_s
FROM last1000
ORDER BY id DESC;
"""

def percentile(sorted_vals, p):
    if not sorted_vals:
        return None
    k = (len(sorted_vals) - 1) * (p / 100)
    f = int(k)
    c = min(f + 1, len(sorted_vals) - 1)
    if f == c:
        return float(sorted_vals[f])
    return float(sorted_vals[f]) * (c - k) + float(sorted_vals[c]) * (k - f)

def main():
    conn = psycopg2.connect(**POSTGRES_CONFIG)
    try:
        with conn.cursor() as cur:
            cur.execute(QUERY)
            rows = cur.fetchall()
            colnames = [d[0] for d in cur.description]

        data = [dict(zip(colnames, r)) for r in rows]

        diffs_raw = [d["diff_raw_s"] for d in data]
        diffs_circ = [d["diff_circular_s"] for d in data]

        diffs_raw_sorted = sorted(diffs_raw)
        diffs_circ_sorted = sorted(diffs_circ)

        print("\n=== DESVIACIÓN TEMPORAL (ignorando horas, usando mm:ss) ===\n")
        print("Definiciones:")
        print("- diff_raw_s      = (mm:ss recibido_en) - (mm:ss hora_utc)")
        print("- diff_circular_s = igual, ajustado a [-1800, +1800] para evitar saltos al cruzar la hora\n")

        def print_stats(name, vals, vals_sorted):
            print(f"--- {name} ---")
            print(f"N            : {len(vals)}")
            print(f"Media (s)    : {mean(vals):.3f}")
            print(f"StdDev (s)   : {pstdev(vals):.3f}")
            print(f"Min / Max (s): {min(vals)} / {max(vals)}")
            print(f"P50 (s)      : {percentile(vals_sorted, 50):.2f}")
            print(f"P95 (s)      : {percentile(vals_sorted, 95):.2f}")
            print()

        print_stats("Desviación RAW", diffs_raw, diffs_raw_sorted)
        print_stats("Desviación CIRCULAR", diffs_circ, diffs_circ_sorted)

        print("Ejemplos (primeros 10 por id DESC):")
        print("id | hora_utc | recibido_en | diff_raw_s | diff_circular_s")
        for d in data[:10]:
            print(f'{d["id"]} | {d["hora_utc"]} | {d["recibido_en"]} | {d["diff_raw_s"]:>10} | {d["diff_circular_s"]:>15}')

        print("\nListo.\n")

    finally:
        conn.close()

if __name__ == "__main__":
    main()
