import os
import json
import time
import statistics
from datetime import timedelta
from pathlib import Path

import psycopg2
import matplotlib
matplotlib.use("Agg")
import matplotlib.pyplot as plt
from pymongo import MongoClient
from bson.int64 import Int64
from dotenv import load_dotenv

# Configuración desde .env
load_dotenv()
PG_URL = os.environ["PG_URL"]
MONGO_URI = os.environ["MONGO_URI"]
RESULTADOS = Path(__file__).resolve().parent.parent / "resultados"

# Mediana en ms de n ejecuciones de una función
def mediana_ms(fn, n):
    tiempos = []
    for _ in range(n):
        t0 = time.perf_counter()
        fn()
        tiempos.append((time.perf_counter() - t0) * 1000)
    return round(statistics.median(tiempos), 3)

def main():
    pg = psycopg2.connect(PG_URL)
    pg.autocommit = True
    cur = pg.cursor()
    col = MongoClient(MONGO_URI)["hce_hospitalizacion"]["telemetria_eventos"]

    # Encuentro y día de Q1 tomados del primer dispositivo con datos reales
    cur.execute("""SELECT d.id_encuentro, min(t.ts)
                   FROM dispositivos d JOIN telemetria_pg t ON t.id_dispositivo = d.id_dispositivo
                   WHERE d.id_dispositivo = (SELECT min(id_dispositivo) FROM dispositivos)
                   GROUP BY d.id_encuentro""")
    enc, ts_ini = cur.fetchone()
    dia_ini = ts_ini.replace(hour=0, minute=0, second=0, microsecond=0)
    dia_fin = dia_ini + timedelta(days=1)

    # Q1: eventos de un encuentro en un día
    def q1_pg():
        cur.execute("SELECT ts, fc, spo2, temp, ta_sis, ta_dia FROM telemetria_pg "
                    "WHERE id_encuentro = %s AND ts >= %s AND ts < %s ORDER BY ts", (enc, dia_ini, dia_fin))
        cur.fetchall()

    def q1_mongo():
        list(col.find({"pg_encuentro_id": Int64(enc), "ts": {"$gte": dia_ini, "$lt": dia_fin}},
                      {"_id": 0, "ts": 1, "metricas": 1}).sort("ts", 1))

    # Q2: promedio de fc por encuentro
    def q2_pg():
        cur.execute("SELECT id_encuentro, avg(fc) FROM telemetria_pg GROUP BY id_encuentro")
        cur.fetchall()

    def q2_mongo():
        list(col.aggregate([{"$group": {"_id": "$pg_encuentro_id", "fc_prom": {"$avg": "$metricas.fc"}}}]))

    # Q3: promedio de fc por paciente con nombre completo
    def q3_pg():
        cur.execute("""SELECT p.id_paciente, p.nombres || ' ' || p.apellidos, avg(t.fc)
                       FROM telemetria_pg t
                       JOIN encuentro_clinico e ON e.id_encuentro = t.id_encuentro
                       JOIN paciente p ON p.id_paciente = e.id_paciente
                       GROUP BY p.id_paciente, p.nombres, p.apellidos""")
        cur.fetchall()

    def q3_hibrida():
        grupos = list(col.aggregate([{"$group": {"_id": "$pg_paciente_id", "fc_prom": {"$avg": "$metricas.fc"}}}]))
        ids = [int(g["_id"]) for g in grupos]
        cur.execute("SELECT id_paciente, nombres || ' ' || apellidos FROM paciente WHERE id_paciente = ANY(%s)", (ids,))
        nombres = dict(cur.fetchall())
        [(g["_id"], nombres.get(int(g["_id"])), g["fc_prom"]) for g in grupos]

    # Q4: flexibilidad de esquema (agregar y quitar campo glucosa)
    def q4_pg():
        cur.execute("ALTER TABLE telemetria_pg ADD COLUMN glucosa int")
        cur.execute("ALTER TABLE telemetria_pg DROP COLUMN glucosa")

    def q4_mongo():
        r = col.insert_one({"pg_paciente_id": Int64(1), "pg_encuentro_id": Int64(enc), "pg_dispositivo_id": Int64(1),
                            "tipo": "monitor", "ts": dia_ini, "metricas": {"fc": 70}, "glucosa": 95})
        col.delete_one({"_id": r.inserted_id})

    # Ejecución: 20 repeticiones (5 en Q4)
    res = {
        "Q1": {"postgres_ms": mediana_ms(q1_pg, 20), "mongodb_ms": mediana_ms(q1_mongo, 20)},
        "Q2": {"postgres_ms": mediana_ms(q2_pg, 20), "mongodb_ms": mediana_ms(q2_mongo, 20)},
        "Q3": {"postgres_ms": mediana_ms(q3_pg, 20), "mongodb_ms": mediana_ms(q3_hibrida, 20)},
        "Q4": {"postgres_ms": mediana_ms(q4_pg, 5), "mongodb_ms": mediana_ms(q4_mongo, 5)},
    }
    RESULTADOS.mkdir(exist_ok=True)
    (RESULTADOS / "benchmark.json").write_text(json.dumps(res, indent=2), encoding="utf-8")

    # Tabla en consola
    print(f"{'Consulta':<8}{'PostgreSQL (ms)':>18}{'MongoDB/Híbrida (ms)':>24}")
    for q, v in res.items():
        print(f"{q:<8}{v['postgres_ms']:>18}{v['mongodb_ms']:>24}")

    # Gráfica de barras con escala logarítmica
    etiquetas = list(res.keys())
    x = range(len(etiquetas))
    ancho = 0.38
    plt.figure(figsize=(8, 5))
    plt.bar([i - ancho / 2 for i in x], [res[q]["postgres_ms"] for q in etiquetas], ancho, label="PostgreSQL")
    plt.bar([i + ancho / 2 for i in x], [res[q]["mongodb_ms"] for q in etiquetas], ancho, label="MongoDB / Híbrida")
    plt.yscale("log")
    plt.xticks(list(x), etiquetas)
    plt.ylabel("Latencia mediana (ms, escala log)")
    plt.title("Latencia por consulta: PostgreSQL vs MongoDB")
    plt.legend()
    plt.tight_layout()
    plt.savefig(RESULTADOS / "latencia.png", dpi=150)

    cur.close()
    pg.close()

if __name__ == "__main__":
    main()