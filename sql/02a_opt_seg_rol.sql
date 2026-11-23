-- 5.000 pacientes
INSERT INTO paciente (tipo_documento, numero_documento, nombres, apellidos, fecha_nacimiento, sexo, municipio_residencia, telefono_contacto)
SELECT 'CC', (2000000000+g)::text, 'Paciente'||g, 'Prueba'||g,
       date '1950-01-01' + (random()*25000)::int,
       (ARRAY['M','F'])[1+(random())::int], 'Medellín', '3'||lpad(g::text,9,'0')
FROM generate_series(1,5000) g;


-- 100.000 encuentros (últimos ~600 días)
INSERT INTO encuentro_clinico (id_paciente, id_profesional, id_hospital, fecha_atencion, tipo_atencion, motivo_consulta, estado)
SELECT 1+floor(random()*5008)::int, 1+floor(random()*5)::int, 1+floor(random()*3)::int,
       now() - random()*600*interval '1 day',
       (ARRAY['consulta_externa','urgencia','control'])[1+floor(random()*3)::int],
       'Motivo sintético '||g,
       (ARRAY['activo','cerrado'])[1+floor(random()*2)::int]
FROM generate_series(1,100000) g;


-- 200.000 prescripciones
INSERT INTO prescripcion (id_encuentro, id_medicamento, dosis, frecuencia, duracion_dias, fecha_prescripcion)
SELECT 1+floor(random()*100000)::int, 1+floor(random()*8)::int, '500 mg', 'cada 8 horas',
       1+floor(random()*14)::int, now() - random()*600*interval '1 day'
FROM generate_series(1,200000) g;


ANALYZE;


-- BASELINE (guardar captura de cada uno)
-- Q1: prescripciones de un encuentro
EXPLAIN (ANALYZE, BUFFERS) SELECT * FROM prescripcion WHERE id_encuentro = 50000;
-- Q2: reporte mensual de medicamentos
EXPLAIN (ANALYZE, BUFFERS)
SELECT m.nombre, count(*) FROM prescripcion p JOIN medicamento m USING (id_medicamento)
WHERE p.fecha_prescripcion >= date '2025-03-01' AND p.fecha_prescripcion < date '2025-04-01'
GROUP BY m.nombre;
-- Q3: historial de un paciente
EXPLAIN (ANALYZE, BUFFERS) SELECT * FROM vw_historial_clinico WHERE id_paciente = 2500 ORDER BY fecha_atencion DESC;
-- Q4: búsqueda por apellido
EXPLAIN (ANALYZE, BUFFERS) SELECT * FROM paciente WHERE apellidos = 'Prueba2500';
-- Q5: encuentros por hospital en los últimos 30 días
EXPLAIN (ANALYZE, BUFFERS) SELECT count(*) FROM encuentro_clinico WHERE id_hospital = 2 AND fecha_atencion >= now() - interval '30 days';


-- ===== FASE 1: ÍNDICES =====
CREATE INDEX idx_paciente_apellidos_nombres ON paciente (apellidos, nombres);
CREATE INDEX idx_encuentro_hospital_fecha   ON encuentro_clinico (id_hospital, fecha_atencion DESC);
-- índice parcial: solo el diagnóstico principal, que usa la vista de historial
CREATE INDEX idx_encdiag_principal ON encuentro_diagnostico (id_encuentro) INCLUDE (id_diagnostico)
    WHERE tipo_diagnostico = 'principal';
-- redundantes (cubiertos por los compuestos): se eliminan para no penalizar escrituras
DROP INDEX IF EXISTS idx_encuentro_paciente;
DROP INDEX IF EXISTS idx_encuentro_hospital;


-- ===== FASE 2A: PARTICIONAMIENTO DE PRESCRIPCION (rango anual) =====
BEGIN;
DROP VIEW IF EXISTS vw_prescripciones_hce;
ALTER TABLE prescripcion RENAME TO prescripcion_old;
ALTER INDEX prescripcion_pkey RENAME TO prescripcion_old_pkey;
DROP INDEX IF EXISTS idx_prescripcion_medicamento;


CREATE TABLE prescripcion (
    id_prescripcion     bigint GENERATED ALWAYS AS IDENTITY,
    id_encuentro        bigint      NOT NULL,
    id_medicamento      bigint      NOT NULL,
    dosis               varchar(50) NOT NULL,
    frecuencia          varchar(50) NOT NULL,
    duracion_dias       integer     NOT NULL,
    fecha_prescripcion  timestamptz NOT NULL DEFAULT now(),
    CONSTRAINT pk_prescripcion PRIMARY KEY (id_prescripcion, fecha_prescripcion),
    CONSTRAINT ck_prescripcion_duracion CHECK (duracion_dias > 0),
    CONSTRAINT fk_prescripcion_encuentro FOREIGN KEY (id_encuentro)
        REFERENCES encuentro_clinico (id_encuentro) ON DELETE CASCADE,
    CONSTRAINT fk_prescripcion_medicamento FOREIGN KEY (id_medicamento)
        REFERENCES medicamento (id_medicamento) ON DELETE RESTRICT
) PARTITION BY RANGE (fecha_prescripcion);


CREATE TABLE prescripcion_2025 PARTITION OF prescripcion FOR VALUES FROM ('2025-01-01') TO ('2026-01-01');
CREATE TABLE prescripcion_2026 PARTITION OF prescripcion FOR VALUES FROM ('2026-01-01') TO ('2027-01-01');
CREATE TABLE prescripcion_2027 PARTITION OF prescripcion FOR VALUES FROM ('2027-01-01') TO ('2028-01-01');
CREATE TABLE prescripcion_default PARTITION OF prescripcion DEFAULT;


INSERT INTO prescripcion (id_prescripcion, id_encuentro, id_medicamento, dosis, frecuencia, duracion_dias, fecha_prescripcion)
OVERRIDING SYSTEM VALUE
SELECT id_prescripcion, id_encuentro, id_medicamento, dosis, frecuencia, duracion_dias, fecha_prescripcion
FROM prescripcion_old;


SELECT setval(pg_get_serial_sequence('prescripcion','id_prescripcion'),
              (SELECT COALESCE(MAX(id_prescripcion),1) FROM prescripcion));
DROP TABLE prescripcion_old;


CREATE INDEX idx_prescripcion_encuentro   ON prescripcion (id_encuentro);
CREATE INDEX idx_prescripcion_medicamento ON prescripcion (id_medicamento);


CREATE OR REPLACE VIEW vw_prescripciones_hce AS
SELECT pres.id_prescripcion, p.id_paciente,
       p.nombres || ' ' || p.apellidos AS paciente_nombre_completo,
       ec.id_encuentro, ec.fecha_atencion,
       m.nombre AS medicamento_nombre, m.concentracion, m.forma_farmaceutica,
       pres.dosis, pres.frecuencia, pres.duracion_dias, pres.fecha_prescripcion,
       pr.nombres || ' ' || pr.apellidos AS profesional_nombre_completo,
       h.nombre AS hospital_nombre
FROM prescripcion pres
JOIN medicamento m         ON m.id_medicamento = pres.id_medicamento
JOIN encuentro_clinico ec  ON ec.id_encuentro  = pres.id_encuentro
JOIN paciente p            ON p.id_paciente    = ec.id_paciente
JOIN profesional_salud pr  ON pr.id_profesional = ec.id_profesional
JOIN hospital h            ON h.id_hospital    = ec.id_hospital;
COMMIT;


-- ===== FASE 2B: AUDITORÍA PARTICIONADA (rango mensual) =====
CREATE TABLE auditoria_hce (
    id_auditoria   bigint GENERATED ALWAYS AS IDENTITY,
    fecha_evento   timestamptz NOT NULL DEFAULT now(),
    usuario_sesion text        NOT NULL,
    rol_efectivo   text,
    tabla          varchar(50) NOT NULL,
    operacion      varchar(10) NOT NULL,
    id_registro    text,
    CONSTRAINT pk_auditoria_hce PRIMARY KEY (id_auditoria, fecha_evento)
) PARTITION BY RANGE (fecha_evento);


CREATE TABLE auditoria_hce_2026_09 PARTITION OF auditoria_hce FOR VALUES FROM ('2026-09-01') TO ('2026-10-01');
CREATE TABLE auditoria_hce_2026_10 PARTITION OF auditoria_hce FOR VALUES FROM ('2026-10-01') TO ('2026-11-01');
CREATE TABLE auditoria_hce_2026_11 PARTITION OF auditoria_hce FOR VALUES FROM ('2026-11-01') TO ('2026-12-01');
CREATE TABLE auditoria_hce_2026_12 PARTITION OF auditoria_hce FOR VALUES FROM ('2026-12-01') TO ('2027-01-01');
CREATE TABLE auditoria_hce_default PARTITION OF auditoria_hce DEFAULT;
CREATE INDEX idx_auditoria_tabla_fecha ON auditoria_hce (tabla, fecha_evento);


COMMENT ON TABLE auditoria_hce IS 'Bitácora de operaciones DML sobre datos clínicos, particionada mensualmente';


-- ===== FASE 3: MEDICIÓN DESPUÉS (repetir Q1–Q5 de 02a y capturar) =====
ANALYZE;
EXPLAIN (ANALYZE, BUFFERS) SELECT * FROM prescripcion WHERE id_encuentro = 50000;
EXPLAIN (ANALYZE, BUFFERS)
SELECT m.nombre, count(*) FROM prescripcion p JOIN medicamento m USING (id_medicamento)
WHERE p.fecha_prescripcion >= date '2025-03-01' AND p.fecha_prescripcion < date '2025-04-01'
GROUP BY m.nombre;   -- debe mostrar solo prescripcion_2025 (poda de particiones)
EXPLAIN (ANALYZE, BUFFERS) SELECT * FROM vw_historial_clinico WHERE id_paciente = 2500 ORDER BY fecha_atencion DESC;
EXPLAIN (ANALYZE, BUFFERS) SELECT * FROM paciente WHERE apellidos = 'Prueba2500';
EXPLAIN (ANALYZE, BUFFERS) SELECT count(*) FROM encuentro_clinico WHERE id_hospital = 2 AND fecha_atencion >= now() - interval '30 days';


-- Evidencia de particiones
SELECT parent.relname AS tabla_padre, child.relname AS particion,
       pg_get_expr(child.relpartbound, child.oid) AS rango
FROM pg_inherits i
JOIN pg_class parent ON parent.oid = i.inhparent
JOIN pg_class child  ON child.oid  = i.inhrelid
WHERE parent.relname IN ('prescripcion','auditoria_hce')
ORDER BY 1, 2;


-- ===== 0. Cerrar la exposición por defecto de Supabase (API anon/authenticated) =====
REVOKE ALL ON ALL TABLES IN SCHEMA public FROM PUBLIC, anon, authenticated;
REVOKE EXECUTE ON ALL ROUTINES IN SCHEMA public FROM PUBLIC, anon, authenticated;


-- ===== 1. Roles =====
DO $$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname='rol_medico')         THEN CREATE ROLE rol_medico NOLOGIN; END IF;
  IF NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname='rol_administrativo') THEN CREATE ROLE rol_administrativo NOLOGIN; END IF;
  IF NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname='rol_auditor')        THEN CREATE ROLE rol_auditor NOLOGIN; END IF;
END $$;


GRANT rol_medico, rol_administrativo, rol_auditor TO postgres;   -- permite SET ROLE para las pruebas
GRANT USAGE ON SCHEMA public TO rol_medico, rol_administrativo, rol_auditor;


-- ===== 2. Vistas enmascaradas =====
CREATE OR REPLACE VIEW vw_paciente_enmascarado AS
SELECT id_paciente, tipo_documento,
       repeat('*', greatest(length(numero_documento)-4,0)) || right(numero_documento,4) AS numero_documento_mask,
       left(nombres,1)   || '***' AS nombres_mask,
       left(apellidos,1) || '***' AS apellidos_mask,
       date_part('year', age(fecha_nacimiento))::int AS edad,
       sexo, municipio_residencia,
       CASE WHEN telefono_contacto IS NULL THEN NULL
            ELSE repeat('*', greatest(length(telefono_contacto)-3,0)) || right(telefono_contacto,3) END AS telefono_mask
FROM paciente;


CREATE OR REPLACE VIEW vw_agenda_administrativa AS
SELECT ec.id_encuentro, ec.id_paciente,
       left(p.nombres,1) || '*** ' || left(p.apellidos,1) || '***' AS paciente_mask,
       ec.fecha_atencion, h.nombre AS hospital,
       pr.nombres || ' ' || pr.apellidos AS profesional,
       ec.tipo_atencion, ec.estado      -- sin motivo de consulta ni diagnóstico
FROM encuentro_clinico ec
JOIN paciente p           ON p.id_paciente = ec.id_paciente
JOIN hospital h           ON h.id_hospital = ec.id_hospital
JOIN profesional_salud pr ON pr.id_profesional = ec.id_profesional;


COMMENT ON VIEW vw_paciente_enmascarado  IS 'Datos de paciente con documento, nombre y teléfono enmascarados';
COMMENT ON VIEW vw_agenda_administrativa IS 'Agenda sin datos clínicos (motivo/diagnóstico) y con paciente enmascarado';


-- ===== 3. Auditoría automática =====
CREATE OR REPLACE FUNCTION fn_auditar() RETURNS trigger
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE v jsonb;
BEGIN
  v := CASE WHEN TG_OP = 'DELETE' THEN to_jsonb(OLD) ELSE to_jsonb(NEW) END;
  INSERT INTO auditoria_hce (usuario_sesion, rol_efectivo, tabla, operacion, id_registro)
  VALUES (session_user, current_setting('role'), TG_TABLE_NAME, TG_OP, v ->> TG_ARGV[0]);
  RETURN NULL;
END $$;


DROP TRIGGER IF EXISTS trg_aud_paciente ON paciente;
CREATE TRIGGER trg_aud_paciente AFTER INSERT OR UPDATE OR DELETE ON paciente
  FOR EACH ROW EXECUTE FUNCTION fn_auditar('id_paciente');
DROP TRIGGER IF EXISTS trg_aud_encuentro ON encuentro_clinico;
CREATE TRIGGER trg_aud_encuentro AFTER INSERT OR UPDATE OR DELETE ON encuentro_clinico
  FOR EACH ROW EXECUTE FUNCTION fn_auditar('id_encuentro');
DROP TRIGGER IF EXISTS trg_aud_prescripcion ON prescripcion;
CREATE TRIGGER trg_aud_prescripcion AFTER INSERT OR UPDATE OR DELETE ON prescripcion
  FOR EACH ROW EXECUTE FUNCTION fn_auditar('id_prescripcion');


-- ===== 4. GRANT: MÉDICO (lectura + inserción limitada; sin UPDATE/DELETE) =====
GRANT SELECT ON hospital, especialidad, profesional_salud, paciente, diagnostico, medicamento,
                encuentro_clinico, encuentro_diagnostico, prescripcion, signos_vitales,
                vw_historial_clinico, vw_prescripciones_hce TO rol_medico;
GRANT INSERT ON encuentro_clinico, encuentro_diagnostico, prescripcion, signos_vitales TO rol_medico;
GRANT EXECUTE ON PROCEDURE sp_crear_encuentro(bigint,bigint,bigint,varchar,text) TO rol_medico;
GRANT EXECUTE ON PROCEDURE sp_registrar_prescripcion(bigint,bigint,varchar,varchar,integer) TO rol_medico;
GRANT EXECUTE ON FUNCTION fn_historial_paciente(bigint), fn_resumen_encuentro(bigint) TO rol_medico;


-- ===== 5. GRANT: ADMINISTRATIVO (solo lecturas específicas, sin datos clínicos) =====
GRANT SELECT ON hospital, especialidad, vw_paciente_enmascarado, vw_agenda_administrativa TO rol_administrativo;
GRANT SELECT (id_profesional, id_hospital, id_especialidad, nombres, apellidos, activo)
      ON profesional_salud TO rol_administrativo;


-- ===== 6. GRANT: AUDITOR (lectura global, sin escritura) =====
GRANT SELECT ON ALL TABLES IN SCHEMA public TO rol_auditor;
GRANT EXECUTE ON FUNCTION fn_historial_paciente(bigint), fn_resumen_encuentro(bigint) TO rol_auditor;


-- Objetos futuros: no otorgar nada por defecto
ALTER DEFAULT PRIVILEGES IN SCHEMA public REVOKE ALL ON TABLES FROM PUBLIC, anon, authenticated;


-- ===== 7. PRUEBAS DE ROLES (resultado en tabla; las escrituras se revierten) =====
CREATE OR REPLACE FUNCTION fn_probar_permiso(p_rol text, p_sql text) RETURNS text
LANGUAGE plpgsql AS $$
BEGIN
  BEGIN
    EXECUTE format('SET LOCAL ROLE %I', p_rol);
    EXECUTE p_sql;
    RAISE EXCEPTION 'OK_SENTINEL';
  EXCEPTION
    WHEN insufficient_privilege THEN RETURN 'DENEGADO';
    WHEN OTHERS THEN
      IF SQLERRM = 'OK_SENTINEL' THEN RETURN 'PERMITIDO'; END IF;
      RETURN 'ERROR: ' || SQLERRM;
  END;
END $$;


SELECT rol, prueba, fn_probar_permiso(rol, sql) AS resultado
FROM (VALUES
 ('rol_medico','SELECT paciente',                 qSELECT * FROM paciente LIMIT 1q),
 ('rol_medico','INSERT prescripcion',             qINSERT INTO prescripcion (id_encuentro,id_medicamento,dosis,frecuencia,duracion_dias) VALUES (1,1,'500 mg','cada 8 horas',3)q),
 ('rol_medico','UPDATE paciente',                 qUPDATE paciente SET telefono_contacto='1' WHERE id_paciente=1q),
 ('rol_medico','DELETE encuentro',                qDELETE FROM encuentro_clinico WHERE id_encuentro=1q),
 ('rol_medico','SELECT auditoria_hce',            qSELECT * FROM auditoria_hce LIMIT 1q),
 ('rol_administrativo','SELECT paciente (tabla)', qSELECT * FROM paciente LIMIT 1q),
 ('rol_administrativo','SELECT vista enmascarada',qSELECT * FROM vw_paciente_enmascarado LIMIT 1q),
 ('rol_administrativo','SELECT vw_historial_clinico', qSELECT * FROM vw_historial_clinico LIMIT 1q),
 ('rol_administrativo','INSERT encuentro',        qINSERT INTO encuentro_clinico (id_paciente,id_profesional,id_hospital,tipo_atencion) VALUES (1,1,1,'control')q),
 ('rol_auditor','SELECT paciente',                qSELECT * FROM paciente LIMIT 1q),
 ('rol_auditor','SELECT auditoria_hce',           qSELECT * FROM auditoria_hce LIMIT 1q),
 ('rol_auditor','INSERT prescripcion',            qINSERT INTO prescripcion (id_encuentro,id_medicamento,dosis,frecuencia,duracion_dias) VALUES (1,1,'x','x',1)q),
 ('rol_auditor','DELETE paciente',                qDELETE FROM paciente WHERE id_paciente=1q)
) AS t(rol, prueba, sql);


-- Demostración visual del enmascaramiento (una a la vez)
SET ROLE rol_administrativo;
SELECT * FROM vw_paciente_enmascarado LIMIT 5;
RESET ROLE;


-- Verificar que la auditoría registra
UPDATE paciente SET telefono_contacto = '3001234567' WHERE id_paciente = 1;
SELECT * FROM auditoria_hce ORDER BY id_auditoria DESC LIMIT 5;


/* 3.1 Consulta para obtener las tablas de una base de datos */
SELECT table_catalog, table_schema, table_name, table_type
FROM information_schema.tables
WHERE table_schema = 'public'
  AND table_name NOT IN (SELECT c.relname FROM pg_class c WHERE c.relispartition)
ORDER BY table_type, table_name;


/* 3.2 Consulta para obtener todas las columnas */
SELECT table_name, ordinal_position, column_name, data_type, is_nullable
FROM information_schema.columns
WHERE table_schema = 'public'
  AND table_name NOT IN (SELECT c.relname FROM pg_class c WHERE c.relispartition)
ORDER BY table_name, ordinal_position;


/* 3.3 Consulta para obtener todas las columnas y tablas relacionadas */
SELECT col.table_name, col.column_name, col.data_type,
       fk.tabla_referenciada, fk.columna_referenciada, fk.constraint_name
FROM information_schema.columns col
LEFT JOIN (
    SELECT cl.relname AS tabla, a.attname AS columna,
           clf.relname AS tabla_referenciada, af.attname AS columna_referenciada, c.conname AS constraint_name
    FROM pg_constraint c
    JOIN pg_class cl  ON cl.oid  = c.conrelid
    JOIN pg_class clf ON clf.oid = c.confrelid
    CROSS JOIN LATERAL unnest(c.conkey, c.confkey) AS k(attnum, fattnum)
    JOIN pg_attribute a  ON a.attrelid  = c.conrelid  AND a.attnum  = k.attnum
    JOIN pg_attribute af ON af.attrelid = c.confrelid AND af.attnum = k.fattnum
    WHERE c.contype = 'f' AND cl.relnamespace = 'public'::regnamespace
) fk ON fk.tabla = col.table_name AND fk.columna = col.column_name
WHERE col.table_schema = 'public'
  AND col.table_name NOT IN (SELECT c.relname FROM pg_class c WHERE c.relispartition)
ORDER BY col.table_name, col.ordinal_position;


/* 3.4 Catálogo, tablas, columnas y valores por defecto */
SELECT table_catalog AS catalogo, table_schema, table_name, column_name, column_default
FROM information_schema.columns
WHERE table_schema = 'public'
  AND table_name NOT IN (SELECT c.relname FROM pg_class c WHERE c.relispartition)
ORDER BY table_name, ordinal_position;


/* 3.5 Tabla, Columna, Tipo de dato, Tamaño del dato */
SELECT table_name AS tabla, column_name AS columna, data_type AS tipo_dato,
       COALESCE(character_maximum_length::text,
                CASE WHEN numeric_precision IS NOT NULL
                     THEN numeric_precision || COALESCE(',' || numeric_scale, '') END) AS tamano
FROM information_schema.columns
WHERE table_schema = 'public'
  AND table_name NOT IN (SELECT c.relname FROM pg_class c WHERE c.relispartition)
ORDER BY table_name, ordinal_positio
