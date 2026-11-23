-- Limpieza idempotente: solo tablas nuevas de telemetría
DROP TABLE IF EXISTS telemetria_pg, dispositivos CASCADE;

-- Dispositivos asociados a un encuentro clínico
CREATE TABLE dispositivos (
    id_dispositivo bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    id_encuentro   bigint NOT NULL,
    tipo           varchar(10) NOT NULL,
    serial         varchar(30) NOT NULL,
    CONSTRAINT uq_dispositivos_serial UNIQUE (serial),
    CONSTRAINT ck_dispositivos_tipo CHECK (tipo IN ('wearable','monitor','oximetro')),
    CONSTRAINT fk_dispositivos_encuentro FOREIGN KEY (id_encuentro) REFERENCES encuentro_clinico (id_encuentro)
);

-- Índice de la FK hacia encuentro_clinico
CREATE INDEX idx_dispositivos_encuentro ON dispositivos (id_encuentro);

-- Lecturas de telemetría (contraparte relacional del benchmark)
CREATE TABLE telemetria_pg (
    id_telemetria  bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    id_dispositivo bigint NOT NULL,
    id_encuentro   bigint NOT NULL,
    ts             timestamptz NOT NULL,
    fc             int,
    spo2           int,
    temp           numeric(4,1),
    ta_sis         int,
    ta_dia         int,
    CONSTRAINT fk_telemetria_dispositivo FOREIGN KEY (id_dispositivo) REFERENCES dispositivos (id_dispositivo),
    CONSTRAINT fk_telemetria_encuentro FOREIGN KEY (id_encuentro) REFERENCES encuentro_clinico (id_encuentro)
);

-- Índices para consultas por encuentro/tiempo y por dispositivo
CREATE INDEX idx_telemetria_encuentro_ts ON telemetria_pg (id_encuentro, ts);
CREATE INDEX idx_telemetria_dispositivo ON telemetria_pg (id_dispositivo);

-- Un dispositivo por cada uno de los primeros 200 encuentros, tipo rotando
INSERT INTO dispositivos (id_encuentro, tipo, serial)
SELECT id_encuentro,
       (ARRAY['wearable','monitor','oximetro'])[1 + ((rn - 1) % 3)::int],
       'SN-' || lpad(rn::text, 6, '0')
FROM (
    SELECT id_encuentro, row_number() OVER (ORDER BY id_encuentro) AS rn
    FROM encuentro_clinico
    ORDER BY id_encuentro
    LIMIT 200
) e
ORDER BY rn;

-- Sin RLS; se cierra el acceso por defecto de Supabase
REVOKE ALL ON dispositivos, telemetria_pg FROM PUBLIC, anon, authenticated;

-- Lectura para roles internos
GRANT SELECT ON dispositivos, telemetria_pg TO rol_medico, rol_auditor;

-- Verificación: debe devolver 200
SELECT count(*) AS total_dispositivos FROM dispositivos;