import os
import json
import time
import random
from datetime import datetime, timedelta, timezone
from pathlib import Path

import psycopg2
from psycopg2.extras import execute_values
from pymongo import MongoClient
from bson.int64 import Int64
from dotenv import load_dotenv

# Configuración desde .env (nunca credenciales en el código)
load_dotenv()
PG_URL = os.environ["PG_URL"]
MONGO_URI = os.environ["MONGO_URI"]
N = int(os.getenv("N_EVENTOS", "100000"))
LOTE = 5000
INICIO = datetime(2026, 10, 1, tzinfo=timezone.utc)
RESULTADOS = Path(__file__).resolve().parent.parent / "resultados"

# Divide una lista en lotes de tamaño fijo
def lotes(lista, tam):
    for i in range(0, len(lista), tam):
        yield lista[i:i + tam]

def main():
    random.seed(42)
    pg = psycopg2.connect(PG_URL)
    cur = pg.cursor()
    mongo = MongoClient(MONGO_URI)
    col = mongo["hce_hospitalizacion"]["telemetria_eventos"]

    # Lectura de dispositivos con su paciente desde Supabase
    cur.execute("""SELECT d.id_dispositivo, d.id_encuentro, e.id_paciente, d.tipo
                   FROM dispositivos d JOIN encuentro_clinico e ON e.id_encuentro = d.id_encuentro
                   ORDER BY d.id_dispositivo""")
    disp = cur.fetchall()
    if not disp:
        raise SystemExit("Sin dispositivos: ejecuta sql/03_telemetria.sql")

    # Generación única en memoria: una lectura cada 10 s por dispositivo
    eventos = []
    for i in range(N):
        id_d, id_e, id_p, tipo = disp[i % len(disp)]
        ts = INICIO + timedelta(seconds=10 * (i // len(disp)))
        fc = random.randint(55, 130)
        spo2 = random.randint(88, 100)
        temp = round(random.uniform(35.5, 39.5), 1)
        sis = random.randint(95, 160)
        dia = random.randint(55, 100)
        pasos = random.randint(0, 40) if tipo == "wearable" else None
        bateria = random.randint(5, 100) if tipo == "wearable" else None
        eventos.append((id_d, id_e, id_p, tipo, ts, fc, spo2, temp, sis, dia, pasos, bateria))

    # Documentos de Mongo con ids de Supabase forzados a Int64
    docs = []
    for id_d, id_e, id_p, tipo, ts, fc, spo2, temp, sis, dia, pasos, bateria in eventos:
        m = {"fc": fc, "spo2": spo2, "temp": temp, "ta_sis": sis, "ta_dia": dia}
        doc = {"pg_paciente_id": Int64(id_p), "pg_encuentro_id": Int64(id_e),
               "pg_dispositivo_id": Int64(id_d), "tipo": tipo, "ts": ts, "metricas": m}
        if tipo == "wearable":
            doc["pasos"] = pasos
            doc["bateria"] = bateria
        docs.append(doc)

    # Filas de Postgres con los mismos datos
    filas = [(e[0], e[1], e[4], e[5], e[6], e[7], e[8], e[9]) for e in eventos]

    # Limpieza previa sin tocar estructura ni índices
    cur.execute("TRUNCATE telemetria_pg RESTART IDENTITY")
    pg.commit()
    col.delete_many({})

    # Ingesta en MongoDB
    t0 = time.perf_counter()
    for lote in lotes(docs, LOTE):
        col.insert_many(lote, ordered=False)
    seg_mongo = time.perf_counter() - t0

    # Ingesta en PostgreSQL con commit por lote
    sql = """INSERT INTO telemetria_pg (id_dispositivo, id_encuentro, ts, fc, spo2, temp, ta_sis, ta_dia)
             VALUES %s"""
    t0 = time.perf_counter()
    for lote in lotes(filas, LOTE):
        execute_values(cur, sql, lote, page_size=LOTE)
        pg.commit()
    seg_pg = time.perf_counter() - t0

    # Resultados por motor
    res = {"n": N,
           "mongodb": {"segundos": round(seg_mongo, 3), "eventos_por_s": round(N / seg_mongo, 1)},
           "postgres": {"segundos": round(seg_pg, 3), "eventos_por_s": round(N / seg_pg, 1)}}
    RESULTADOS.mkdir(exist_ok=True)
    (RESULTADOS / "ingesta.json").write_text(json.dumps(res, indent=2), encoding="utf-8")
    print(json.dumps(res, indent=2))

    # Conteos finales (deben coincidir con N)
    cur.execute("SELECT count(*) FROM telemetria_pg")
    n_pg = cur.fetchone()[0]
    n_mongo = col.count_documents({})
    print("Conteo PostgreSQL:", n_pg, "| Conteo MongoDB:", n_mongo, "| Esperado:", N)

    cur.close()
    pg.close()
    mongo.close()

if __name__ == "__main__":
    main()