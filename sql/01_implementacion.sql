-- =====================================================================
-- HCE BÁSICA — RED DE HOSPITALES PÚBLICOS GOBERNACIÓN DE ANTIOQUIA
-- Script de IMPLEMENTACIÓN — PostgreSQL / Supabase
-- Contiene: tablas, índices, comentarios, vistas, funciones,
-- procedimientos y triggers. No contiene datos ni pruebas.
-- =====================================================================




-- =====================================================================
-- 1. TABLAS DE CATÁLOGO INDEPENDIENTES
-- =====================================================================




CREATE TABLE hospital (
    id_hospital     bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    nombre          varchar(150) NOT NULL,
    municipio       varchar(100) NOT NULL,
    nivel_atencion  varchar(5)   NOT NULL,
    created_at      timestamptz  NOT NULL DEFAULT now(),
    updated_at      timestamptz  NOT NULL DEFAULT now(),
    CONSTRAINT uq_hospital_nombre UNIQUE (nombre),
    CONSTRAINT ck_hospital_nivel_atencion CHECK (nivel_atencion IN ('I','II','III'))
);




CREATE TABLE especialidad (
    id_especialidad bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    nombre          varchar(100) NOT NULL,
    CONSTRAINT uq_especialidad_nombre UNIQUE (nombre)
);




CREATE TABLE diagnostico (
    id_diagnostico  bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    codigo_cie10    varchar(10)  NOT NULL,
    descripcion     text         NOT NULL,
    CONSTRAINT uq_diagnostico_cie10 UNIQUE (codigo_cie10)
);




CREATE TABLE medicamento (
    id_medicamento      bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    nombre              varchar(150) NOT NULL,
    forma_farmaceutica  varchar(50)  NOT NULL,
    concentracion       varchar(30),
    CONSTRAINT uq_medicamento_nombre_conc_forma
        UNIQUE (nombre, concentracion, forma_farmaceutica)
);




-- =====================================================================
-- 2. ENTIDADES PRINCIPALES
-- =====================================================================




CREATE TABLE profesional_salud (
    id_profesional          bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    id_hospital             bigint NOT NULL,
    id_especialidad         bigint NOT NULL,
    nombres                 varchar(100) NOT NULL,
    apellidos               varchar(100) NOT NULL,
    numero_registro_medico  varchar(30)  NOT NULL,
    activo                  boolean      NOT NULL DEFAULT true,
    created_at              timestamptz  NOT NULL DEFAULT now(),
    updated_at              timestamptz  NOT NULL DEFAULT now(),
    CONSTRAINT uq_profesional_registro UNIQUE (numero_registro_medico),
    CONSTRAINT fk_profesional_hospital
        FOREIGN KEY (id_hospital) REFERENCES hospital (id_hospital)
        ON DELETE RESTRICT,
    CONSTRAINT fk_profesional_especialidad
        FOREIGN KEY (id_especialidad) REFERENCES especialidad (id_especialidad)
        ON DELETE RESTRICT
);




CREATE TABLE paciente (
    id_paciente             bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    tipo_documento          varchar(5)   NOT NULL,
    numero_documento        varchar(20)  NOT NULL,
    nombres                 varchar(100) NOT NULL,
    apellidos               varchar(100) NOT NULL,
    fecha_nacimiento        date         NOT NULL,
    sexo                    varchar(10),
    municipio_residencia    varchar(100),
    telefono_contacto       varchar(20),
    created_at              timestamptz  NOT NULL DEFAULT now(),
    updated_at              timestamptz  NOT NULL DEFAULT now(),
    CONSTRAINT uq_paciente_documento UNIQUE (tipo_documento, numero_documento),
    CONSTRAINT ck_paciente_tipo_documento
        CHECK (tipo_documento IN ('CC','TI','CE','RC','PA')),
    CONSTRAINT ck_paciente_sexo
        CHECK (sexo IS NULL OR sexo IN ('M','F','Otro'))
    -- NOTA: el CHECK original ck_paciente_fecha_nacimiento se elimina
    -- más abajo (sección 12) y se reemplaza por un trigger, para poder
    -- generar un mensaje de error más descriptivo.
);




-- =====================================================================
-- 3. EVENTO CLÍNICO CENTRAL
-- =====================================================================




CREATE TABLE encuentro_clinico (
    id_encuentro     bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    id_paciente      bigint NOT NULL,
    id_profesional   bigint NOT NULL,
    id_hospital      bigint NOT NULL,
    fecha_atencion   timestamptz  NOT NULL DEFAULT now(),
    tipo_atencion    varchar(20)  NOT NULL,
    motivo_consulta  text,
    estado           varchar(15)  NOT NULL DEFAULT 'activo',
    created_at       timestamptz  NOT NULL DEFAULT now(),
    updated_at       timestamptz  NOT NULL DEFAULT now(),
    CONSTRAINT ck_encuentro_tipo_atencion
        CHECK (tipo_atencion IN ('consulta_externa','urgencia','control')),
    CONSTRAINT ck_encuentro_estado
        CHECK (estado IN ('activo','cerrado')),
    -- fecha_atencion <= now() se valida con trigger (sección 12)
    CONSTRAINT fk_encuentro_paciente
        FOREIGN KEY (id_paciente) REFERENCES paciente (id_paciente)
        ON DELETE RESTRICT,
    CONSTRAINT fk_encuentro_profesional
        FOREIGN KEY (id_profesional) REFERENCES profesional_salud (id_profesional)
        ON DELETE RESTRICT,
    CONSTRAINT fk_encuentro_hospital
        FOREIGN KEY (id_hospital) REFERENCES hospital (id_hospital)
        ON DELETE RESTRICT
);




-- =====================================================================
-- 4. TABLA ASOCIATIVA N:M
-- =====================================================================




CREATE TABLE encuentro_diagnostico (
    id_encuentro     bigint NOT NULL,
    id_diagnostico   bigint NOT NULL,
    tipo_diagnostico varchar(15) NOT NULL DEFAULT 'relacionado',
    PRIMARY KEY (id_encuentro, id_diagnostico),
    CONSTRAINT ck_encdiag_tipo_diagnostico
        CHECK (tipo_diagnostico IN ('principal','relacionado')),
    -- "máximo un diagnóstico principal por encuentro" se valida con trigger (sección 12)
    CONSTRAINT fk_encdiag_encuentro
        FOREIGN KEY (id_encuentro) REFERENCES encuentro_clinico (id_encuentro)
        ON DELETE CASCADE,
    CONSTRAINT fk_encdiag_diagnostico
        FOREIGN KEY (id_diagnostico) REFERENCES diagnostico (id_diagnostico)
        ON DELETE RESTRICT
);




-- =====================================================================
-- 5. PRESCRIPCIÓN
-- =====================================================================




CREATE TABLE prescripcion (
    id_prescripcion     bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    id_encuentro        bigint NOT NULL,
    id_medicamento      bigint NOT NULL,
    dosis               varchar(50) NOT NULL,
    frecuencia          varchar(50) NOT NULL,
    duracion_dias       integer     NOT NULL,
    fecha_prescripcion  timestamptz NOT NULL DEFAULT now(),
    CONSTRAINT ck_prescripcion_duracion CHECK (duracion_dias > 0),
    CONSTRAINT fk_prescripcion_encuentro
        FOREIGN KEY (id_encuentro) REFERENCES encuentro_clinico (id_encuentro)
        ON DELETE CASCADE,
    CONSTRAINT fk_prescripcion_medicamento
        FOREIGN KEY (id_medicamento) REFERENCES medicamento (id_medicamento)
        ON DELETE RESTRICT
);




-- =====================================================================
-- 6. SIGNOS VITALES (1:1 CON ENCUENTRO_CLINICO)
-- =====================================================================




CREATE TABLE signos_vitales (
    id_encuentro         bigint PRIMARY KEY,
    tension_sistolica    numeric(5,2),
    tension_diastolica   numeric(5,2),
    frecuencia_cardiaca  integer,
    temperatura          numeric(4,2),
    peso_kg              numeric(5,2),
    talla_cm             numeric(5,2),
    CONSTRAINT ck_signos_tension_sistolica
        CHECK (tension_sistolica IS NULL OR tension_sistolica > 0),
    CONSTRAINT ck_signos_tension_diastolica
        CHECK (tension_diastolica IS NULL OR tension_diastolica > 0),
    CONSTRAINT ck_signos_frecuencia_cardiaca
        CHECK (frecuencia_cardiaca IS NULL OR frecuencia_cardiaca > 0),
    CONSTRAINT ck_signos_temperatura
        CHECK (temperatura IS NULL OR temperatura BETWEEN 30 AND 45),
    CONSTRAINT ck_signos_peso
        CHECK (peso_kg IS NULL OR peso_kg > 0),
    CONSTRAINT ck_signos_talla
        CHECK (talla_cm IS NULL OR talla_cm > 0),
    CONSTRAINT fk_signos_encuentro
        FOREIGN KEY (id_encuentro) REFERENCES encuentro_clinico (id_encuentro)
        ON DELETE CASCADE
);




-- =====================================================================
-- 7. ÍNDICES ADICIONALES (más allá de los de PK/UNIQUE)
-- =====================================================================




CREATE INDEX idx_encuentro_paciente
    ON encuentro_clinico (id_paciente);




CREATE INDEX idx_encuentro_profesional
    ON encuentro_clinico (id_profesional);




CREATE INDEX idx_encuentro_hospital
    ON encuentro_clinico (id_hospital);




CREATE INDEX idx_encuentro_fecha
    ON encuentro_clinico (fecha_atencion);




CREATE INDEX idx_encuentro_paciente_fecha
    ON encuentro_clinico (id_paciente, fecha_atencion);




CREATE INDEX idx_encdiag_diagnostico
    ON encuentro_diagnostico (id_diagnostico);




CREATE INDEX idx_prescripcion_medicamento
    ON prescripcion (id_medicamento);




CREATE INDEX idx_profesional_hospital
    ON profesional_salud (id_hospital);




CREATE INDEX idx_profesional_especialidad
    ON profesional_salud (id_especialidad);




-- =====================================================================
-- 8. COMENTARIOS PARA DOCUMENTACIÓN AUTOMÁTICA
-- =====================================================================




COMMENT ON TABLE hospital IS 'Sedes de la red pública de hospitales de la Gobernación de Antioquia';
COMMENT ON COLUMN hospital.nivel_atencion IS 'Nivel de complejidad del hospital: I, II o III';




COMMENT ON TABLE especialidad IS 'Catálogo de especialidades médicas';




COMMENT ON TABLE profesional_salud IS 'Personal médico/asistencial que atiende dentro de la red';
COMMENT ON COLUMN profesional_salud.activo IS 'Indica si el profesional puede recibir nuevos encuentros clínicos';
COMMENT ON COLUMN profesional_salud.numero_registro_medico IS 'Registro médico oficial, único por profesional';




COMMENT ON TABLE paciente IS 'Pacientes atendidos en la red, independientes de un hospital fijo';
COMMENT ON COLUMN paciente.tipo_documento IS 'Tipo de documento de identidad (CC, TI, CE, RC, PA)';
COMMENT ON COLUMN paciente.numero_documento IS 'Número de documento; único junto con tipo_documento';




COMMENT ON TABLE encuentro_clinico IS 'Evento clínico central: cada fila es una atención concreta';
COMMENT ON COLUMN encuentro_clinico.fecha_atencion IS 'Fecha y hora real de la atención; no puede ser futura (validado por trigger)';
COMMENT ON COLUMN encuentro_clinico.estado IS 'Estado del encuentro: activo o cerrado';




COMMENT ON TABLE diagnostico IS 'Catálogo de diagnósticos tipo CIE-10 simplificado';




COMMENT ON TABLE encuentro_diagnostico IS 'Tabla asociativa que resuelve la relación N:M entre encuentro_clinico y diagnostico';
COMMENT ON COLUMN encuentro_diagnostico.tipo_diagnostico IS 'Rol del diagnóstico en el encuentro: principal o relacionado';




COMMENT ON TABLE medicamento IS 'Catálogo de medicamentos disponibles en la red';




COMMENT ON TABLE prescripcion IS 'Prescripción de un medicamento dentro de un encuentro clínico';
COMMENT ON COLUMN prescripcion.duracion_dias IS 'Duración del tratamiento en días; debe ser mayor que cero';




COMMENT ON TABLE signos_vitales IS 'Signos vitales tomados en un encuentro clínico (relación 1:1)';




-- =====================================================================
-- 9. VISTAS
-- =====================================================================




CREATE OR REPLACE VIEW vw_historial_clinico AS
SELECT
    ec.id_encuentro,
    p.id_paciente,
    p.tipo_documento,
    p.numero_documento,
    p.nombres || ' ' || p.apellidos          AS paciente_nombre_completo,
    ec.fecha_atencion,
    h.nombre                                  AS hospital_nombre,
    pr.nombres || ' ' || pr.apellidos         AS profesional_nombre_completo,
    ec.tipo_atencion,
    ec.estado,
    (
        SELECT d.descripcion
        FROM encuentro_diagnostico ed
        JOIN diagnostico d ON d.id_diagnostico = ed.id_diagnostico
        WHERE ed.id_encuentro = ec.id_encuentro
          AND ed.tipo_diagnostico = 'principal'
        LIMIT 1
    ) AS diagnostico_principal
FROM encuentro_clinico ec
JOIN paciente p            ON p.id_paciente = ec.id_paciente
JOIN hospital h             ON h.id_hospital = ec.id_hospital
JOIN profesional_salud pr   ON pr.id_profesional = ec.id_profesional;




COMMENT ON VIEW vw_historial_clinico IS 'Historial clínico consolidado por encuentro, con diagnóstico principal';




CREATE OR REPLACE VIEW vw_prescripciones_hce AS
SELECT
    pres.id_prescripcion,
    p.id_paciente,
    p.nombres || ' ' || p.apellidos      AS paciente_nombre_completo,
    ec.id_encuentro,
    ec.fecha_atencion,
    m.nombre                              AS medicamento_nombre,
    m.concentracion,
    m.forma_farmaceutica,
    pres.dosis,
    pres.frecuencia,
    pres.duracion_dias,
    pres.fecha_prescripcion,
    pr.nombres || ' ' || pr.apellidos     AS profesional_nombre_completo,
    h.nombre                              AS hospital_nombre
FROM prescripcion pres
JOIN medicamento m           ON m.id_medicamento = pres.id_medicamento
JOIN encuentro_clinico ec    ON ec.id_encuentro = pres.id_encuentro
JOIN paciente p               ON p.id_paciente = ec.id_paciente
JOIN profesional_salud pr    ON pr.id_profesional = ec.id_profesional
JOIN hospital h               ON h.id_hospital = ec.id_hospital;




COMMENT ON VIEW vw_prescripciones_hce IS 'Prescripciones con contexto completo de paciente, encuentro, profesional y hospital';




-- =====================================================================
-- 10. FUNCIONES
-- =====================================================================




CREATE OR REPLACE FUNCTION fn_historial_paciente(p_id_paciente bigint)
RETURNS TABLE (
    id_encuentro          bigint,
    fecha_atencion        timestamptz,
    hospital_nombre       varchar,
    profesional_nombre    text,
    tipo_atencion         varchar,
    estado                varchar,
    diagnostico_principal text
)
LANGUAGE plpgsql
AS $$
BEGIN
    IF NOT EXISTS (SELECT 1 FROM paciente WHERE id_paciente = p_id_paciente) THEN
        RAISE EXCEPTION 'El paciente con id % no existe', p_id_paciente;
    END IF;




    RETURN QUERY
    SELECT
        v.id_encuentro,
        v.fecha_atencion,
        v.hospital_nombre,
        v.profesional_nombre_completo,
        v.tipo_atencion,
        v.estado,
        v.diagnostico_principal
    FROM vw_historial_clinico v
    WHERE v.id_paciente = p_id_paciente
    ORDER BY v.fecha_atencion DESC;
END;
$$;




CREATE OR REPLACE FUNCTION fn_resumen_encuentro(p_id_encuentro bigint)
RETURNS TABLE (
    id_encuentro           bigint,
    estado                 varchar,
    total_diagnosticos     bigint,
    total_medicamentos     bigint,
    tiene_signos_vitales   boolean
)
LANGUAGE plpgsql
AS $$
BEGIN
    IF NOT EXISTS (SELECT 1 FROM encuentro_clinico ec WHERE ec.id_encuentro = p_id_encuentro) THEN
        RAISE EXCEPTION 'El encuentro clínico con id % no existe', p_id_encuentro;
    END IF;




    RETURN QUERY
    SELECT
        ec.id_encuentro,
        ec.estado,
        (SELECT COUNT(*) FROM encuentro_diagnostico ed WHERE ed.id_encuentro = ec.id_encuentro),
        (SELECT COUNT(*) FROM prescripcion pr WHERE pr.id_encuentro = ec.id_encuentro),
        EXISTS (SELECT 1 FROM signos_vitales sv WHERE sv.id_encuentro = ec.id_encuentro)
    FROM encuentro_clinico ec
    WHERE ec.id_encuentro = p_id_encuentro;
END;
$$;




-- =====================================================================
-- 11. PROCEDIMIENTOS ALMACENADOS
-- =====================================================================




CREATE OR REPLACE PROCEDURE sp_crear_encuentro(
    p_id_paciente     bigint,
    p_id_profesional  bigint,
    p_id_hospital     bigint,
    p_tipo_atencion   varchar,
    p_motivo_consulta text
)
LANGUAGE plpgsql
AS $$
DECLARE
    v_id_encuentro bigint;
BEGIN
    IF NOT EXISTS (SELECT 1 FROM paciente WHERE id_paciente = p_id_paciente) THEN
        RAISE EXCEPTION 'No existe el paciente con id %', p_id_paciente;
    END IF;




    IF NOT EXISTS (SELECT 1 FROM profesional_salud WHERE id_profesional = p_id_profesional) THEN
        RAISE EXCEPTION 'No existe el profesional con id %', p_id_profesional;
    END IF;




    IF NOT EXISTS (SELECT 1 FROM hospital WHERE id_hospital = p_id_hospital) THEN
        RAISE EXCEPTION 'No existe el hospital con id %', p_id_hospital;
    END IF;




    -- fecha_atencion, estado, created_at y updated_at usan su DEFAULT
    INSERT INTO encuentro_clinico (id_paciente, id_profesional, id_hospital, tipo_atencion, motivo_consulta)
    VALUES (p_id_paciente, p_id_profesional, p_id_hospital, p_tipo_atencion, p_motivo_consulta)
    RETURNING id_encuentro INTO v_id_encuentro;




    RAISE NOTICE 'Encuentro clínico creado con id_encuentro = %', v_id_encuentro;
END;
$$;




CREATE OR REPLACE PROCEDURE sp_registrar_prescripcion(
    p_id_encuentro    bigint,
    p_id_medicamento  bigint,
    p_dosis           varchar,
    p_frecuencia      varchar,
    p_duracion_dias   integer
)
LANGUAGE plpgsql
AS $$
DECLARE
    v_id_prescripcion bigint;
BEGIN
    IF NOT EXISTS (SELECT 1 FROM encuentro_clinico WHERE id_encuentro = p_id_encuentro) THEN
        RAISE EXCEPTION 'No existe el encuentro clínico con id %', p_id_encuentro;
    END IF;




    IF NOT EXISTS (SELECT 1 FROM medicamento WHERE id_medicamento = p_id_medicamento) THEN
        RAISE EXCEPTION 'No existe el medicamento con id %', p_id_medicamento;
    END IF;




    IF p_duracion_dias <= 0 THEN
        RAISE EXCEPTION 'La duración en días debe ser mayor que cero (recibido: %)', p_duracion_dias;
    END IF;




    -- fecha_prescripcion usa su DEFAULT
    INSERT INTO prescripcion (id_encuentro, id_medicamento, dosis, frecuencia, duracion_dias)
    VALUES (p_id_encuentro, p_id_medicamento, p_dosis, p_frecuencia, p_duracion_dias)
    RETURNING id_prescripcion INTO v_id_prescripcion;




    RAISE NOTICE 'Prescripción registrada con id_prescripcion = %', v_id_prescripcion;
END;
$$;




-- =====================================================================
-- 12. TRIGGERS Y FUNCIONES DE VALIDACIÓN
-- =====================================================================




-- 12.1 fecha_atencion no puede ser futura
CREATE OR REPLACE FUNCTION fn_validar_fecha_encuentro()
RETURNS trigger
LANGUAGE plpgsql
AS $$
BEGIN
    IF NEW.fecha_atencion > now() THEN
        RAISE EXCEPTION
            'fecha_atencion (%) no puede ser posterior al momento actual (%)',
            NEW.fecha_atencion, now();  
    END IF;
    RETURN NEW;
END;
$$;




DROP TRIGGER IF EXISTS trg_validar_fecha_encuentro ON encuentro_clinico;




CREATE TRIGGER trg_validar_fecha_encuentro
    BEFORE INSERT OR UPDATE ON encuentro_clinico
    FOR EACH ROW
    EXECUTE FUNCTION fn_validar_fecha_encuentro();




-- 12.2 Máximo un diagnóstico "principal" por encuentro
CREATE OR REPLACE FUNCTION fn_validar_diagnostico_principal()
RETURNS trigger
LANGUAGE plpgsql
AS $$
BEGIN
    IF NEW.tipo_diagnostico = 'principal' THEN
        IF EXISTS (
            SELECT 1
            FROM encuentro_diagnostico ed
            WHERE ed.id_encuentro = NEW.id_encuentro
              AND ed.tipo_diagnostico = 'principal'
              AND ed.id_diagnostico <> NEW.id_diagnostico
        ) THEN
            RAISE EXCEPTION
                'El encuentro % ya tiene un diagnóstico principal registrado',
                NEW.id_encuentro;
        END IF;
    END IF;
    RETURN NEW;
END;
$$;




DROP TRIGGER IF EXISTS trg_validar_diagnostico_principal ON encuentro_diagnostico;




CREATE TRIGGER trg_validar_diagnostico_principal
    BEFORE INSERT OR UPDATE ON encuentro_diagnostico
    FOR EACH ROW
    EXECUTE FUNCTION fn_validar_diagnostico_principal();




-- 12.3 Profesional inactivo no puede recibir nuevos encuentros (solo INSERT)
CREATE OR REPLACE FUNCTION fn_validar_profesional_activo()
RETURNS trigger
LANGUAGE plpgsql
AS $$
DECLARE
    v_activo boolean;
BEGIN
    SELECT activo INTO v_activo
    FROM profesional_salud
    WHERE id_profesional = NEW.id_profesional;




    IF v_activo IS FALSE THEN
        RAISE EXCEPTION
            'El profesional % está inactivo y no puede recibir nuevos encuentros clínicos',
            NEW.id_profesional;
    END IF;




    RETURN NEW;
END;
$$;




DROP TRIGGER IF EXISTS trg_validar_profesional_activo ON encuentro_clinico;




CREATE TRIGGER trg_validar_profesional_activo
    BEFORE INSERT ON encuentro_clinico
    FOR EACH ROW
    EXECUTE FUNCTION fn_validar_profesional_activo();




-- 12.4 Actualización automática de updated_at
CREATE OR REPLACE FUNCTION fn_set_updated_at()
RETURNS trigger
LANGUAGE plpgsql
AS $$
BEGIN
    NEW.updated_at = now();
    RETURN NEW;
END;
$$;




DROP TRIGGER IF EXISTS trg_hospital_updated_at ON hospital;
CREATE TRIGGER trg_hospital_updated_at
    BEFORE UPDATE ON hospital
    FOR EACH ROW
    EXECUTE FUNCTION fn_set_updated_at();




DROP TRIGGER IF EXISTS trg_profesional_updated_at ON profesional_salud;
CREATE TRIGGER trg_profesional_updated_at
    BEFORE UPDATE ON profesional_salud
    FOR EACH ROW
    EXECUTE FUNCTION fn_set_updated_at();




DROP TRIGGER IF EXISTS trg_paciente_updated_at ON paciente;
CREATE TRIGGER trg_paciente_updated_at
    BEFORE UPDATE ON paciente
    FOR EACH ROW
    EXECUTE FUNCTION fn_set_updated_at();




DROP TRIGGER IF EXISTS trg_encuentro_updated_at ON encuentro_clinico;
CREATE TRIGGER trg_encuentro_updated_at
    BEFORE UPDATE ON encuentro_clinico
    FOR EACH ROW
    EXECUTE FUNCTION fn_set_updated_at();




-- 12.5 fecha_nacimiento no puede ser futura (reemplaza el CHECK original
-- para poder dar un mensaje de error descriptivo)
ALTER TABLE paciente
    DROP CONSTRAINT IF EXISTS ck_paciente_fecha_nacimiento;




CREATE OR REPLACE FUNCTION fn_validar_fecha_nacimiento()
RETURNS trigger
LANGUAGE plpgsql
AS $$
BEGIN
    IF NEW.fecha_nacimiento > CURRENT_DATE THEN
        RAISE EXCEPTION
            'fecha_nacimiento (%) no puede ser posterior a la fecha actual (%)',
            NEW.fecha_nacimiento, CURRENT_DATE;
    END IF;
    RETURN NEW;
END;
$$;




DROP TRIGGER IF EXISTS trg_validar_fecha_nacimiento ON paciente;




CREATE TRIGGER trg_validar_fecha_nacimiento
    BEFORE INSERT OR UPDATE ON paciente
    FOR EACH ROW
    EXECUTE FUNCTION fn_validar_fecha_nacimiento();




-- =====================================================================
-- 13. CONSULTAS DE VALIDACIÓN DEL ESQUEMA (solo lectura)
-- =====================================================================




-- 13.1 Existencia de las 10 tablas base
SELECT table_name
FROM information_schema.tables
WHERE table_schema = 'public'
  AND table_name IN (
      'hospital','especialidad','profesional_salud','paciente',
      'encuentro_clinico','diagnostico','encuentro_diagnostico',
      'medicamento','prescripcion','signos_vitales'
  )
ORDER BY table_name;




-- 13.2 Columnas por tabla
SELECT table_name, column_name, data_type, is_nullable, column_default
FROM information_schema.columns
WHERE table_schema = 'public'
  AND table_name IN (
      'hospital','especialidad','profesional_salud','paciente',
      'encuentro_clinico','diagnostico','encuentro_diagnostico',
      'medicamento','prescripcion','signos_vitales'
  )
ORDER BY table_name, ordinal_position;




-- 13.3 Claves primarias
SELECT tc.table_name, kcu.column_name, tc.constraint_name
FROM information_schema.table_constraints tc
JOIN information_schema.key_column_usage kcu
  ON tc.constraint_name = kcu.constraint_name
WHERE tc.constraint_type = 'PRIMARY KEY'
  AND tc.table_schema = 'public'
ORDER BY tc.table_name, kcu.ordinal_position;




-- 13.4 Claves foráneas
SELECT
    tc.table_name AS tabla_origen,
    kcu.column_name AS columna_fk,
    ccu.table_name AS tabla_referenciada,
    ccu.column_name AS columna_referenciada,
    rc.delete_rule
FROM information_schema.table_constraints tc
JOIN information_schema.key_column_usage kcu
  ON tc.constraint_name = kcu.constraint_name
JOIN information_schema.constraint_column_usage ccu
  ON tc.constraint_name = ccu.constraint_name
JOIN information_schema.referential_constraints rc
  ON tc.constraint_name = rc.constraint_name
WHERE tc.constraint_type = 'FOREIGN KEY'
  AND tc.table_schema = 'public'
ORDER BY tc.table_name;




-- 13.5 Restricciones UNIQUE y CHECK
SELECT tc.table_name, tc.constraint_name, tc.constraint_type
FROM information_schema.table_constraints tc
WHERE tc.constraint_type IN ('UNIQUE','CHECK')
  AND tc.table_schema = 'public'
ORDER BY tc.table_name, tc.constraint_type;




-- 13.6 Índices creados
SELECT indexname, tablename, indexdef
FROM pg_indexes
WHERE schemaname = 'public'
ORDER BY tablename, indexname;




-- =====================================================================
-- REGLAS DE NEGOCIO — ESTADO DE IMPLEMENTACIÓN
-- =====================================================================
-- 1. fecha_atencion no futura                         -> IMPLEMENTADO (trg_validar_fecha_encuentro)
-- 2. Máximo un diagnóstico "principal" por encuentro   -> IMPLEMENTADO (trg_validar_diagnostico_principal)
-- 3. Profesional inactivo no recibe nuevos encuentros  -> IMPLEMENTADO (trg_validar_profesional_activo)
-- 4. updated_at automático en hospital/profesional/
--    paciente/encuentro_clinico                        -> IMPLEMENTADO (fn_set_updated_at + triggers)
-- 5. Auditoría detallada, roles/GRANT-REVOKE, vistas
--    enmascaradas, RLS, particionamiento por fecha      -> PENDIENTE (fase siguiente del proyecto)




-- Pruebas
-- =====================================================================
-- HCE BÁSICA — RED DE HOSPITALES PÚBLICOS GOBERNACIÓN DE ANTIOQUIA
-- Script de PRUEBAS — PostgreSQL / Supabase
-- Requiere haber ejecutado antes 01_implementacion.sql
-- Contiene: datos semilla, consultas de verificación y casos de error.
-- =====================================================================




-- =====================================================================
-- 1. HOSPITAL
-- =====================================================================
INSERT INTO hospital (nombre, municipio, nivel_atencion) VALUES
('Hospital Público del Oriente Antioqueño', 'Rionegro', 'II'),
('Hospital Regional de Urabá',              'Apartadó', 'II'),
('Hospital Universitario Central de Antioquia', 'Medellín', 'III');




-- =====================================================================
-- 2. ESPECIALIDAD
-- =====================================================================
INSERT INTO especialidad (nombre) VALUES
('Medicina General'),
('Medicina Interna'),
('Pediatría'),
('Cardiología'),
('Urgencias');




-- =====================================================================
-- 3. PROFESIONAL_SALUD
-- =====================================================================
INSERT INTO profesional_salud (id_hospital, id_especialidad, nombres, apellidos, numero_registro_medico, activo)
VALUES
((SELECT id_hospital FROM hospital WHERE nombre = 'Hospital Público del Oriente Antioqueño'),
 (SELECT id_especialidad FROM especialidad WHERE nombre = 'Medicina General'),
 'Carlos', 'Ramírez', 'RM-1001', true),




((SELECT id_hospital FROM hospital WHERE nombre = 'Hospital Público del Oriente Antioqueño'),
 (SELECT id_especialidad FROM especialidad WHERE nombre = 'Pediatría'),
 'Luisa', 'Fernández', 'RM-1002', true),




((SELECT id_hospital FROM hospital WHERE nombre = 'Hospital Regional de Urabá'),
 (SELECT id_especialidad FROM especialidad WHERE nombre = 'Medicina Interna'),
 'Andrés', 'Gómez', 'RM-1003', true),




((SELECT id_hospital FROM hospital WHERE nombre = 'Hospital Regional de Urabá'),
 (SELECT id_especialidad FROM especialidad WHERE nombre = 'Urgencias'),
 'Paula', 'Restrepo', 'RM-1004', true),




((SELECT id_hospital FROM hospital WHERE nombre = 'Hospital Universitario Central de Antioquia'),
 (SELECT id_especialidad FROM especialidad WHERE nombre = 'Cardiología'),
 'Jorge', 'Londoño', 'RM-1005', true),




-- Este profesional se marca como inactivo en la sección 9 (pruebas de error)
((SELECT id_hospital FROM hospital WHERE nombre = 'Hospital Universitario Central de Antioquia'),
 (SELECT id_especialidad FROM especialidad WHERE nombre = 'Medicina General'),
 'Marcela', 'Zapata', 'RM-1006', true);




-- =====================================================================
-- 4. PACIENTE
-- =====================================================================
INSERT INTO paciente (tipo_documento, numero_documento, nombres, apellidos, fecha_nacimiento, sexo, municipio_residencia, telefono_contacto)
VALUES
('CC', '1001001001', 'Mariana',  'Osorio',   '1990-04-12', 'F', 'Rionegro', '3000000001'),
('TI', '1002002002', 'Samuel',   'Pérez',    '2010-08-01', 'M', 'Apartadó', '3000000002'),
('CE', '1003003003', 'Laura',    'Gómez',    '1985-01-23', 'F', 'Medellín', '3000000003'),
('RC', '1004004004', 'Emilio',   'Torres',   '2019-11-05', 'M', 'Andes',    '3000000004'),
('PA', '1005005005', 'Sofía',    'Martínez', '1978-06-30', 'F', 'Rionegro', '3000000005'),
('CC', '1006006006', 'Julián',   'Herrera',  '1995-09-18', 'M', 'Medellín', '3000000006'),
('TI', '1007007007', 'Valentina','Cano',     '2008-02-14', 'F', 'Apartadó', '3000000007'),
('CC', '1008008008', 'Ricardo',  'Muñoz',    '1966-12-01', 'M', 'Rionegro', '3000000008');




-- =====================================================================
-- 5. DIAGNOSTICO
-- =====================================================================
INSERT INTO diagnostico (codigo_cie10, descripcion) VALUES
('Z00.0', 'Examen general sin hallazgos anormales'),
('I10',   'Hipertensión arterial esencial'),
('E11',   'Diabetes mellitus tipo 2'),
('J06.9', 'Infección aguda de las vías respiratorias superiores, no especificada'),
('A09',   'Diarrea y gastroenteritis de presunto origen infeccioso'),
('M54.5', 'Dolor lumbar'),
('R51',   'Cefalea'),
('J45',   'Asma');




-- =====================================================================
-- 6. MEDICAMENTO
-- =====================================================================
INSERT INTO medicamento (nombre, forma_farmaceutica, concentracion) VALUES
('Acetaminofén', 'Tableta',    '500 mg'),
('Ibuprofeno',   'Tableta',    '400 mg'),
('Amoxicilina',  'Cápsula',    '500 mg'),
('Losartán',     'Tableta',    '50 mg'),
('Metformina',   'Tableta',    '850 mg'),
('Salbutamol',   'Inhalador',  '100 mcg'),
('Loratadina',   'Tableta',    '10 mg'),
('Suero Oral',   'Sobre',      '27.9 g');




-- =====================================================================
-- 7. ENCUENTROS CLÍNICOS Y DATOS RELACIONADOS (E1–E12)
-- =====================================================================




-- E1: Mariana Osorio — control general — Hospital 1 — con signos vitales
DO $$
DECLARE
    v_id_encuentro bigint;
BEGIN
    INSERT INTO encuentro_clinico (id_paciente, id_profesional, id_hospital, fecha_atencion, tipo_atencion, motivo_consulta, estado)
    VALUES (
        (SELECT id_paciente FROM paciente WHERE tipo_documento='CC' AND numero_documento='1001001001'),
        (SELECT id_profesional FROM profesional_salud WHERE numero_registro_medico='RM-1001'),
        (SELECT id_hospital FROM hospital WHERE nombre='Hospital Público del Oriente Antioqueño'),
        now() - interval '10 days', 'consulta_externa', 'Control general', 'cerrado'
    ) RETURNING id_encuentro INTO v_id_encuentro;




    RAISE NOTICE 'E1 creado con id_encuentro = %', v_id_encuentro;




    INSERT INTO encuentro_diagnostico (id_encuentro, id_diagnostico, tipo_diagnostico)
    VALUES (v_id_encuentro, (SELECT id_diagnostico FROM diagnostico WHERE codigo_cie10='Z00.0'), 'principal');




    INSERT INTO signos_vitales (id_encuentro, tension_sistolica, tension_diastolica, frecuencia_cardiaca, temperatura, peso_kg, talla_cm)
    VALUES (v_id_encuentro, 118, 76, 72, 36.5, 68.2, 165.0);
END $$;




-- E2: Mariana Osorio — dolor en el pecho — Hospital 3 (Cardiología)
DO $$
DECLARE
    v_id_encuentro bigint;
BEGIN
    INSERT INTO encuentro_clinico (id_paciente, id_profesional, id_hospital, fecha_atencion, tipo_atencion, motivo_consulta, estado)
    VALUES (
        (SELECT id_paciente FROM paciente WHERE tipo_documento='CC' AND numero_documento='1001001001'),
        (SELECT id_profesional FROM profesional_salud WHERE numero_registro_medico='RM-1005'),
        (SELECT id_hospital FROM hospital WHERE nombre='Hospital Universitario Central de Antioquia'),
        now() - interval '5 days', 'consulta_externa', 'Dolor en el pecho', 'activo'
    ) RETURNING id_encuentro INTO v_id_encuentro;




    RAISE NOTICE 'E2 creado con id_encuentro = %', v_id_encuentro;




    INSERT INTO encuentro_diagnostico (id_encuentro, id_diagnostico, tipo_diagnostico)
    VALUES (v_id_encuentro, (SELECT id_diagnostico FROM diagnostico WHERE codigo_cie10='I10'), 'principal');




    INSERT INTO prescripcion (id_encuentro, id_medicamento, dosis, frecuencia, duracion_dias)
    VALUES (v_id_encuentro, (SELECT id_medicamento FROM medicamento WHERE nombre='Losartán'), '50 mg', 'cada 24 horas', 30);
END $$;




-- E3: Samuel Pérez — control de crecimiento — Hospital 1 (Pediatría)
DO $$
DECLARE
    v_id_encuentro bigint;
BEGIN
    INSERT INTO encuentro_clinico (id_paciente, id_profesional, id_hospital, fecha_atencion, tipo_atencion, motivo_consulta, estado)
    VALUES (
        (SELECT id_paciente FROM paciente WHERE tipo_documento='TI' AND numero_documento='1002002002'),
        (SELECT id_profesional FROM profesional_salud WHERE numero_registro_medico='RM-1002'),
        (SELECT id_hospital FROM hospital WHERE nombre='Hospital Público del Oriente Antioqueño'),
        now() - interval '8 days', 'consulta_externa', 'Control de crecimiento', 'cerrado'
    ) RETURNING id_encuentro INTO v_id_encuentro;




    RAISE NOTICE 'E3 creado con id_encuentro = %', v_id_encuentro;




    INSERT INTO encuentro_diagnostico (id_encuentro, id_diagnostico, tipo_diagnostico)
    VALUES (v_id_encuentro, (SELECT id_diagnostico FROM diagnostico WHERE codigo_cie10='Z00.0'), 'principal');
END $$;




-- E4: Laura Gómez — fiebre alta — Hospital 2 — dos diagnósticos + signos + prescripción
DO $$
DECLARE
    v_id_encuentro bigint;
BEGIN
    INSERT INTO encuentro_clinico (id_paciente, id_profesional, id_hospital, fecha_atencion, tipo_atencion, motivo_consulta, estado)
    VALUES (
        (SELECT id_paciente FROM paciente WHERE tipo_documento='CE' AND numero_documento='1003003003'),
        (SELECT id_profesional FROM profesional_salud WHERE numero_registro_medico='RM-1003'),
        (SELECT id_hospital FROM hospital WHERE nombre='Hospital Regional de Urabá'),
        now() - interval '3 days', 'urgencia', 'Fiebre alta', 'cerrado'
    ) RETURNING id_encuentro INTO v_id_encuentro;




    RAISE NOTICE 'E4 creado con id_encuentro = %', v_id_encuentro;




    INSERT INTO encuentro_diagnostico (id_encuentro, id_diagnostico, tipo_diagnostico) VALUES
    (v_id_encuentro, (SELECT id_diagnostico FROM diagnostico WHERE codigo_cie10='J06.9'), 'principal'),
    (v_id_encuentro, (SELECT id_diagnostico FROM diagnostico WHERE codigo_cie10='R51'),   'relacionado');




    INSERT INTO signos_vitales (id_encuentro, tension_sistolica, tension_diastolica, frecuencia_cardiaca, temperatura, peso_kg, talla_cm)
    VALUES (v_id_encuentro, 110, 70, 98, 39.2, 58.0, 162.0);




    INSERT INTO prescripcion (id_encuentro, id_medicamento, dosis, frecuencia, duracion_dias)
    VALUES (v_id_encuentro, (SELECT id_medicamento FROM medicamento WHERE nombre='Amoxicilina'), '500 mg', 'cada 8 horas', 7);
END $$;




-- E5: Emilio Torres — tos persistente — Hospital 1
DO $$
DECLARE
    v_id_encuentro bigint;
BEGIN
    INSERT INTO encuentro_clinico (id_paciente, id_profesional, id_hospital, fecha_atencion, tipo_atencion, motivo_consulta, estado)
    VALUES (
        (SELECT id_paciente FROM paciente WHERE tipo_documento='RC' AND numero_documento='1004004004'),
        (SELECT id_profesional FROM profesional_salud WHERE numero_registro_medico='RM-1002'),
        (SELECT id_hospital FROM hospital WHERE nombre='Hospital Público del Oriente Antioqueño'),
        now() - interval '1 day', 'consulta_externa', 'Tos persistente', 'activo'
    ) RETURNING id_encuentro INTO v_id_encuentro;




    RAISE NOTICE 'E5 creado con id_encuentro = %', v_id_encuentro;




    INSERT INTO encuentro_diagnostico (id_encuentro, id_diagnostico, tipo_diagnostico)
    VALUES (v_id_encuentro, (SELECT id_diagnostico FROM diagnostico WHERE codigo_cie10='J06.9'), 'principal');
END $$;




-- E6: Sofía Martínez — dolor abdominal — Hospital 2 — dos diagnósticos + signos + 2 prescripciones
DO $$
DECLARE
    v_id_encuentro bigint;
BEGIN
    INSERT INTO encuentro_clinico (id_paciente, id_profesional, id_hospital, fecha_atencion, tipo_atencion, motivo_consulta, estado)
    VALUES (
        (SELECT id_paciente FROM paciente WHERE tipo_documento='PA' AND numero_documento='1005005005'),
        (SELECT id_profesional FROM profesional_salud WHERE numero_registro_medico='RM-1004'),
        (SELECT id_hospital FROM hospital WHERE nombre='Hospital Regional de Urabá'),
        now() - interval '2 days', 'urgencia', 'Dolor abdominal intenso', 'cerrado'
    ) RETURNING id_encuentro INTO v_id_encuentro;




    RAISE NOTICE 'E6 creado con id_encuentro = %', v_id_encuentro;




    INSERT INTO encuentro_diagnostico (id_encuentro, id_diagnostico, tipo_diagnostico) VALUES
    (v_id_encuentro, (SELECT id_diagnostico FROM diagnostico WHERE codigo_cie10='A09'), 'principal'),
    (v_id_encuentro, (SELECT id_diagnostico FROM diagnostico WHERE codigo_cie10='R51'), 'relacionado');




    INSERT INTO signos_vitales (id_encuentro, tension_sistolica, tension_diastolica, frecuencia_cardiaca, temperatura, peso_kg, talla_cm)
    VALUES (v_id_encuentro, 105, 68, 88, 37.8, 60.5, 160.0);




    INSERT INTO prescripcion (id_encuentro, id_medicamento, dosis, frecuencia, duracion_dias) VALUES
    (v_id_encuentro, (SELECT id_medicamento FROM medicamento WHERE nombre='Suero Oral'),  '1 sobre', 'después de cada deposición', 3),
    (v_id_encuentro, (SELECT id_medicamento FROM medicamento WHERE nombre='Ibuprofeno'), '400 mg',  'cada 8 horas', 3);
END $$;




-- E7: Julián Herrera — control de hipertensión — Hospital 3
DO $$
DECLARE
    v_id_encuentro bigint;
BEGIN
    INSERT INTO encuentro_clinico (id_paciente, id_profesional, id_hospital, fecha_atencion, tipo_atencion, motivo_consulta, estado)
    VALUES (
        (SELECT id_paciente FROM paciente WHERE tipo_documento='CC' AND numero_documento='1006006006'),
        (SELECT id_profesional FROM profesional_salud WHERE numero_registro_medico='RM-1006'),
        (SELECT id_hospital FROM hospital WHERE nombre='Hospital Universitario Central de Antioquia'),
        now() - interval '15 days', 'control', 'Control de hipertensión', 'cerrado'
    ) RETURNING id_encuentro INTO v_id_encuentro;




    RAISE NOTICE 'E7 creado con id_encuentro = %', v_id_encuentro;




    INSERT INTO encuentro_diagnostico (id_encuentro, id_diagnostico, tipo_diagnostico)
    VALUES (v_id_encuentro, (SELECT id_diagnostico FROM diagnostico WHERE codigo_cie10='I10'), 'principal');
END $$;




-- E8: Valentina Cano — palpitaciones — Hospital 3 (Cardiología)
DO $$
DECLARE
    v_id_encuentro bigint;
BEGIN
    INSERT INTO encuentro_clinico (id_paciente, id_profesional, id_hospital, fecha_atencion, tipo_atencion, motivo_consulta, estado)
    VALUES (
        (SELECT id_paciente FROM paciente WHERE tipo_documento='TI' AND numero_documento='1007007007'),
        (SELECT id_profesional FROM profesional_salud WHERE numero_registro_medico='RM-1005'),
        (SELECT id_hospital FROM hospital WHERE nombre='Hospital Universitario Central de Antioquia'),
        now() - interval '6 days', 'consulta_externa', 'Palpitaciones ocasionales', 'activo'
    ) RETURNING id_encuentro INTO v_id_encuentro;




    RAISE NOTICE 'E8 creado con id_encuentro = %', v_id_encuentro;




    INSERT INTO encuentro_diagnostico (id_encuentro, id_diagnostico, tipo_diagnostico)
    VALUES (v_id_encuentro, (SELECT id_diagnostico FROM diagnostico WHERE codigo_cie10='I10'), 'principal');




    INSERT INTO prescripcion (id_encuentro, id_medicamento, dosis, frecuencia, duracion_dias)
    VALUES (v_id_encuentro, (SELECT id_medicamento FROM medicamento WHERE nombre='Losartán'), '50 mg', 'cada 24 horas', 15);
END $$;




-- E9: Ricardo Muñoz — chequeo anual — Hospital 1 — con signos vitales
DO $$
DECLARE
    v_id_encuentro bigint;
BEGIN
    INSERT INTO encuentro_clinico (id_paciente, id_profesional, id_hospital, fecha_atencion, tipo_atencion, motivo_consulta, estado)
    VALUES (
        (SELECT id_paciente FROM paciente WHERE tipo_documento='CC' AND numero_documento='1008008008'),
        (SELECT id_profesional FROM profesional_salud WHERE numero_registro_medico='RM-1001'),
        (SELECT id_hospital FROM hospital WHERE nombre='Hospital Público del Oriente Antioqueño'),
        now() - interval '20 days', 'consulta_externa', 'Chequeo médico anual', 'cerrado'
    ) RETURNING id_encuentro INTO v_id_encuentro;




    RAISE NOTICE 'E9 creado con id_encuentro = %', v_id_encuentro;




    INSERT INTO encuentro_diagnostico (id_encuentro, id_diagnostico, tipo_diagnostico)
    VALUES (v_id_encuentro, (SELECT id_diagnostico FROM diagnostico WHERE codigo_cie10='Z00.0'), 'principal');




    INSERT INTO signos_vitales (id_encuentro, tension_sistolica, tension_diastolica, frecuencia_cardiaca, temperatura, peso_kg, talla_cm)
    VALUES (v_id_encuentro, 130, 85, 76, 36.7, 82.0, 172.0);
END $$;




-- E10: Ricardo Muñoz — dolor lumbar agudo — Hospital 2 — con signos + 2 prescripciones
DO $$
DECLARE
    v_id_encuentro bigint;
BEGIN
    INSERT INTO encuentro_clinico (id_paciente, id_profesional, id_hospital, fecha_atencion, tipo_atencion, motivo_consulta, estado)
    VALUES (
        (SELECT id_paciente FROM paciente WHERE tipo_documento='CC' AND numero_documento='1008008008'),
        (SELECT id_profesional FROM profesional_salud WHERE numero_registro_medico='RM-1004'),
        (SELECT id_hospital FROM hospital WHERE nombre='Hospital Regional de Urabá'),
        now() - interval '4 days', 'urgencia', 'Dolor lumbar agudo', 'cerrado'
    ) RETURNING id_encuentro INTO v_id_encuentro;




    RAISE NOTICE 'E10 creado con id_encuentro = %', v_id_encuentro;




    INSERT INTO encuentro_diagnostico (id_encuentro, id_diagnostico, tipo_diagnostico)
    VALUES (v_id_encuentro, (SELECT id_diagnostico FROM diagnostico WHERE codigo_cie10='M54.5'), 'principal');




    INSERT INTO signos_vitales (id_encuentro, tension_sistolica, tension_diastolica, frecuencia_cardiaca, temperatura, peso_kg, talla_cm)
    VALUES (v_id_encuentro, 125, 82, 80, 36.9, 82.5, 172.0);




    INSERT INTO prescripcion (id_encuentro, id_medicamento, dosis, frecuencia, duracion_dias) VALUES
    (v_id_encuentro, (SELECT id_medicamento FROM medicamento WHERE nombre='Ibuprofeno'),   '400 mg', 'cada 8 horas', 5),
    (v_id_encuentro, (SELECT id_medicamento FROM medicamento WHERE nombre='Acetaminofén'), '500 mg', 'cada 6 horas', 3);
END $$;




-- E11: Mariana Osorio — seguimiento de control — Hospital 1 — sin diagnóstico/signos/prescripción
DO $$
DECLARE
    v_id_encuentro bigint;
BEGIN
    INSERT INTO encuentro_clinico (id_paciente, id_profesional, id_hospital, fecha_atencion, tipo_atencion, motivo_consulta, estado)
    VALUES (
        (SELECT id_paciente FROM paciente WHERE tipo_documento='CC' AND numero_documento='1001001001'),
        (SELECT id_profesional FROM profesional_salud WHERE numero_registro_medico='RM-1001'),
        (SELECT id_hospital FROM hospital WHERE nombre='Hospital Público del Oriente Antioqueño'),
        now() - interval '1 day', 'control', 'Seguimiento de control programado', 'activo'
    ) RETURNING id_encuentro INTO v_id_encuentro;




    RAISE NOTICE 'E11 creado con id_encuentro = %', v_id_encuentro;
END $$;




-- E12: Laura Gómez — consulta de rutina — Hospital 2 — sin diagnóstico/signos/prescripción
DO $$
DECLARE
    v_id_encuentro bigint;
BEGIN
    INSERT INTO encuentro_clinico (id_paciente, id_profesional, id_hospital, fecha_atencion, tipo_atencion, motivo_consulta, estado)
    VALUES (
        (SELECT id_paciente FROM paciente WHERE tipo_documento='CE' AND numero_documento='1003003003'),
        (SELECT id_profesional FROM profesional_salud WHERE numero_registro_medico='RM-1003'),
        (SELECT id_hospital FROM hospital WHERE nombre='Hospital Regional de Urabá'),
        now() - interval '12 days', 'consulta_externa', 'Consulta de rutina', 'cerrado'
    ) RETURNING id_encuentro INTO v_id_encuentro;




    RAISE NOTICE 'E12 creado con id_encuentro = %', v_id_encuentro;
END $$;




-- =====================================================================
-- 8. CONSULTAS DE VERIFICACIÓN
-- =====================================================================




-- A. Pacientes registrados
SELECT id_paciente, tipo_documento, numero_documento, nombres, apellidos, fecha_nacimiento, sexo
FROM paciente
ORDER BY id_paciente;




-- B. Profesionales con su hospital y especialidad
SELECT
    ps.id_profesional, ps.nombres, ps.apellidos, ps.numero_registro_medico, ps.activo,
    h.nombre AS hospital, e.nombre AS especialidad
FROM profesional_salud ps
JOIN hospital h ON h.id_hospital = ps.id_hospital
JOIN especialidad e ON e.id_especialidad = ps.id_especialidad
ORDER BY ps.id_profesional;




-- C. Encuentros con paciente, profesional y hospital
SELECT
    ec.id_encuentro, ec.fecha_atencion, ec.tipo_atencion, ec.estado,
    p.nombres || ' ' || p.apellidos   AS paciente,
    pr.nombres || ' ' || pr.apellidos AS profesional,
    h.nombre AS hospital
FROM encuentro_clinico ec
JOIN paciente p ON p.id_paciente = ec.id_paciente
JOIN profesional_salud pr ON pr.id_profesional = ec.id_profesional
JOIN hospital h ON h.id_hospital = ec.id_hospital
ORDER BY ec.fecha_atencion DESC;




-- D. Historial clínico (vista)
SELECT * FROM vw_historial_clinico ORDER BY fecha_atencion DESC;




-- E. Prescripciones (vista)
SELECT * FROM vw_prescripciones_hce ORDER BY fecha_prescripcion DESC;




-- F. Función historial de paciente (Mariana Osorio tiene 3 encuentros)
SELECT * FROM fn_historial_paciente(
    (SELECT id_paciente FROM paciente WHERE tipo_documento='CC' AND numero_documento='1001001001')
);




-- G.1 Resumen de encuentro con diagnósticos, medicamentos y signos vitales (E6 — Sofía Martínez)
SELECT * FROM fn_resumen_encuentro(
    (SELECT id_encuentro FROM encuentro_clinico WHERE motivo_consulta = 'Dolor abdominal intenso')
);




-- G.2 Resumen de encuentro con menos información (E11 — sin diagnóstico/signos/prescripción)
SELECT * FROM fn_resumen_encuentro(
    (SELECT id_encuentro FROM encuentro_clinico WHERE motivo_consulta = 'Seguimiento de control programado')
);




-- H. Procedimiento: crear un nuevo encuentro (caso exitoso)
DO $$
DECLARE v_pac bigint; v_prof bigint; v_hosp bigint;
BEGIN
    SELECT id_paciente INTO v_pac FROM paciente WHERE tipo_documento='TI' AND numero_documento='1002002002';
    SELECT id_profesional INTO v_prof FROM profesional_salud WHERE numero_registro_medico='RM-1002';
    SELECT id_hospital INTO v_hosp FROM hospital WHERE nombre='Hospital Público del Oriente Antioqueño';
    CALL sp_crear_encuentro(v_pac, v_prof, v_hosp, 'control', 'Control de vacunación');
END $$;




SELECT id_encuentro, fecha_atencion, estado
FROM encuentro_clinico
WHERE motivo_consulta = 'Control de vacunación';




-- I. Procedimiento: registrar una prescripción (caso exitoso)
DO $$
DECLARE v_enc bigint; v_med bigint;
BEGIN
    SELECT id_encuentro INTO v_enc FROM encuentro_clinico WHERE motivo_consulta = 'Control de vacunación';
    SELECT id_medicamento INTO v_med FROM medicamento WHERE nombre='Acetaminofén';
    CALL sp_registrar_prescripcion(v_enc, v_med, '250 mg', 'cada 8 horas si hay fiebre', 3);
END $$;




SELECT * FROM prescripcion
WHERE id_encuentro = (SELECT id_encuentro FROM encuentro_clinico WHERE motivo_consulta = 'Control de vacunación');




-- =====================================================================
-- 9. PRUEBAS DE VALIDACIÓN Y ERRORES ESPERADOS
-- =====================================================================




-- 9.1 Fecha de atención futura → debe fallar (trg_validar_fecha_encuentro)
INSERT INTO encuentro_clinico (id_paciente, id_profesional, id_hospital, fecha_atencion, tipo_atencion, motivo_consulta)
VALUES (
    (SELECT id_paciente FROM paciente WHERE tipo_documento='CC' AND numero_documento='1001001001'),
    (SELECT id_profesional FROM profesional_salud WHERE numero_registro_medico='RM-1001'),
    (SELECT id_hospital FROM hospital WHERE nombre='Hospital Público del Oriente Antioqueño'),
    now() + interval '2 days', 'consulta_externa', 'Prueba fecha futura (debe fallar)'
);
-- Esperado: EXCEPTION 'fecha_atencion (...) no puede ser posterior al momento actual (...)'




-- 9.2 Segundo diagnóstico principal en el mismo encuentro → debe fallar (trg_validar_diagnostico_principal)
-- (E1 ya tiene Z00.0 como principal)
INSERT INTO encuentro_diagnostico (id_encuentro, id_diagnostico, tipo_diagnostico)
VALUES (
    (SELECT id_encuentro FROM encuentro_clinico WHERE motivo_consulta = 'Control general'),
    (SELECT id_diagnostico FROM diagnostico WHERE codigo_cie10 = 'I10'),
    'principal'
);
-- Esperado: EXCEPTION 'El encuentro ... ya tiene un diagnóstico principal registrado'




-- 9.3 Profesional inactivo no puede recibir nuevos encuentros → debe fallar (trg_validar_profesional_activo)
UPDATE profesional_salud SET activo = false WHERE numero_registro_medico = 'RM-1006';




DO $$
DECLARE v_pac bigint; v_prof bigint; v_hosp bigint;
BEGIN
    SELECT id_paciente INTO v_pac FROM paciente WHERE tipo_documento='CC' AND numero_documento='1006006006';
    SELECT id_profesional INTO v_prof FROM profesional_salud WHERE numero_registro_medico='RM-1006';
    SELECT id_hospital INTO v_hosp FROM hospital WHERE nombre='Hospital Universitario Central de Antioquia';
    CALL sp_crear_encuentro(v_pac, v_prof, v_hosp, 'consulta_externa', 'Prueba profesional inactivo (debe fallar)');
END $$;
-- Esperado: EXCEPTION 'El profesional ... está inactivo y no puede recibir nuevos encuentros clínicos'




-- Confirmar que SÍ se puede actualizar un encuentro ya existente de ese profesional (no debe fallar,
-- el trigger trg_validar_profesional_activo solo aplica a INSERT)
UPDATE encuentro_clinico
SET estado = 'cerrado'
WHERE motivo_consulta = 'Control de hipertensión';




-- 9.4 Fecha de nacimiento futura → debe fallar (trg_validar_fecha_nacimiento)
UPDATE paciente
SET fecha_nacimiento = CURRENT_DATE + 1
WHERE tipo_documento='CC' AND numero_documento='1001001001';
-- Esperado: EXCEPTION 'fecha_nacimiento (...) no puede ser posterior a la fecha actual (...)'




-- 9.5 Duración de prescripción igual a 0 → debe fallar
-- 9.5.a Vía procedimiento (validación explícita en PL/pgSQL)
DO $$
DECLARE v_enc bigint; v_med bigint;
BEGIN
    SELECT id_encuentro INTO v_enc FROM encuentro_clinico WHERE motivo_consulta = 'Fiebre alta';
    SELECT id_medicamento INTO v_med FROM medicamento WHERE nombre = 'Ibuprofeno';
    CALL sp_registrar_prescripcion(v_enc, v_med, '400 mg', 'cada 8 horas', 0);
END $$;
-- Esperado: EXCEPTION 'La duración en días debe ser mayor que cero (recibido: 0)'




-- 9.5.b Vía INSERT directo (demuestra el CHECK de la tabla)
INSERT INTO prescripcion (id_encuentro, id_medicamento, dosis, frecuencia, duracion_dias)
VALUES (
    (SELECT id_encuentro FROM encuentro_clinico WHERE motivo_consulta = 'Fiebre alta'),
    (SELECT id_medicamento FROM medicamento WHERE nombre = 'Ibuprofeno'),
    '400 mg', 'cada 8 horas', 0
);
-- Esperado: ERROR de violación de check constraint "ck_prescripcion_duracion"




-- 9.6 sp_crear_encuentro con paciente inexistente → debe fallar
CALL sp_crear_encuentro(999999, 1, 1, 'urgencia', 'Prueba de error: paciente inexistente');
-- Esperado: EXCEPTION 'No existe el paciente con id 999999'




-- 9.7 Verificación del trigger updated_at (campo no crítico: telefono_contacto)
SELECT id_paciente, telefono_contacto, updated_at AS updated_at_antes
FROM paciente
WHERE tipo_documento='TI' AND numero_documento='1007007007';




UPDATE paciente
SET telefono_contacto = '3009999999'
WHERE tipo_documento='TI' AND numero_documento='1007007007';




SELECT id_paciente, telefono_contacto, updated_at AS updated_at_despues
FROM paciente
WHERE tipo_documento='TI' AND numero_documento='1007007007';
-- El segundo updated_at debe ser mayor (más reciente) que el primero