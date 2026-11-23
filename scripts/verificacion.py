import os

import psycopg2
from pymongo import MongoClient
from dotenv import load_dotenv

# Configuración desde .env
load_dotenv()
PG_URL = os.environ["PG_URL"]
MONGO_URI = os.environ["MONGO_URI"]

def main():
    pg = psycopg2.connect(PG_URL)
    cur = pg.cursor()
    col = MongoClient(MONGO_URI)["hce_hospitalizacion"]["telemetria_eventos"]

    # Conteos de ambos motores
    cur.execute("SELECT count(*) FROM telemetria_pg")
    n_pg = cur.fetchone()[0]
    n_mongo = col.count_documents({})
    print("Conteo PostgreSQL:", n_pg, "| Conteo MongoDB:", n_mongo)

    # Encuentros distintos de Mongo que no existen en Supabase
    ids_mongo = [int(i) for i in col.distinct("pg_encuentro_id")]
    cur.execute("SELECT id_encuentro FROM encuentro_clinico WHERE id_encuentro = ANY(%s)", (ids_mongo,))
    existentes = {r[0] for r in cur.fetchall()}
    huerfanos = sorted(set(ids_mongo) - existentes)

    # Resultado final
    if not huerfanos and n_pg == n_mongo:
        print("OK")
    else:
        print("Huérfanos:", huerfanos)
        print("Conteos coinciden:", n_pg == n_mongo)

    cur.close()
    pg.close()

if __name__ == "__main__":
    main()