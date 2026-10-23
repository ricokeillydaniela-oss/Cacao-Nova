-- =====================================================================================
-- CACAO NOVA - MODELO DE DATOS V2

SET client_encoding = 'UTF8';

CREATE EXTENSION IF NOT EXISTS pgcrypto;  -- claves con bcrypt y tokens aleatorios

-- Hora de Colombia para toda la base (las ventas y cosechas se agrupan por dia y mes)
DO $$ BEGIN EXECUTE format('ALTER DATABASE %I SET timezone TO %L', current_database(), 'America/Bogota'); END $$;
SET timezone = 'America/Bogota';

DROP VIEW  IF EXISTS vw_labores_trabajador;
DROP VIEW  IF EXISTS vw_mano_obra;
DROP TABLE IF EXISTS tab_analisis_calidad;
DROP TABLE IF EXISTS tab_inventario_insumos;
DROP TABLE IF EXISTS tab_jornales;
DROP TABLE IF EXISTS tab_venta_detalle;
DROP TABLE IF EXISTS tab_ventas;
DROP TABLE IF EXISTS tab_inventario_bodega;
DROP TABLE IF EXISTS tab_bodega;
DROP TABLE IF EXISTS tab_secado;
DROP TABLE IF EXISTS tab_fermentacion;
DROP TABLE IF EXISTS tab_recoleccion;
DROP TABLE IF EXISTS tab_alerta_climatica;
DROP TABLE IF EXISTS tab_registro_climatico;
DROP TABLE IF EXISTS tab_monitoreo_plaga_det;
DROP TABLE IF EXISTS tab_tratamiento_aplicado;
DROP TABLE IF EXISTS tab_incidencia_sanitaria;
DROP TABLE IF EXISTS tab_monitoreo_periodico;
DROP TABLE IF EXISTS tab_aplicacion_insumo;
DROP TABLE IF EXISTS tab_catalogo_insumo;
DROP TABLE IF EXISTS tab_catalogo_tratamiento;
DROP TABLE IF EXISTS tab_catalogo_plaga;
DROP TABLE IF EXISTS tab_cosecha;
DROP TABLE IF EXISTS tab_meta_produccion;
DROP TABLE IF EXISTS tab_alertas_enviadas;
DROP TABLE IF EXISTS tab_monitoreo_siembra;
DROP TABLE IF EXISTS tab_siembra;
DROP TABLE IF EXISTS tab_activ_lote;
DROP TABLE IF EXISTS tab_lote_productivo;
DROP TABLE IF EXISTS tab_analisis_suelo;
DROP TABLE IF EXISTS tab_preparacion_lotes;
DROP TABLE IF EXISTS tab_calendario_agricola;
DROP TABLE IF EXISTS tab_actividades;
DROP TABLE IF EXISTS tab_lotes;
DROP TABLE IF EXISTS tab_catalogo_calidad_cacao;
DROP TABLE IF EXISTS tab_catalogo_herramienta;
DROP TABLE IF EXISTS tab_unidad_medida;
DROP TABLE IF EXISTS tab_fincas_personas;
DROP TABLE IF EXISTS tab_finca_variedad;
DROP TABLE IF EXISTS tab_catalogo_variedad;
DROP TABLE IF EXISTS tab_finca;
DROP TABLE IF EXISTS tab_trabajadores;
DROP TABLE IF EXISTS tab_tecnico;
DROP TABLE IF EXISTS tab_productor;
DROP VIEW  IF EXISTS vw_historial_cambios;
DROP TABLE IF EXISTS tab_auditoria;
DROP TABLE IF EXISTS tab_finalidades_tratamiento;
DROP TABLE IF EXISTS tab_persona_roles;
DROP TABLE IF EXISTS tab_rol_permisos;
DROP TABLE IF EXISTS tab_permisos;
DROP TABLE IF EXISTS tab_roles;
DROP TABLE IF EXISTS tab_parametros_seguridad;
DROP TABLE IF EXISTS tab_accesos_auditoria;
DROP TABLE IF EXISTS tab_tokens_usuario;
DROP TABLE IF EXISTS tab_sesiones;
DROP TABLE IF EXISTS tab_usuarios;
DROP TABLE IF EXISTS tab_personas;
DROP TABLE IF EXISTS tab_ciudades;
DROP TABLE IF EXISTS tab_dptos;
DROP TABLE IF EXISTS tab_parametros;


CREATE TABLE IF NOT EXISTS tab_parametros
(
    id_parametro         INT    NOT NULL CHECK (id_parametro > 0),
    producto             VARCHAR(50) NOT NULL CHECK (BTRIM(producto) <> ''),
    tiempo_produccion    INTEGER     NOT NULL CHECK (tiempo_produccion >= 0),
    precio_referencia    NUMERIC(14,2) NOT NULL CHECK (precio_referencia >= 0),
    PRIMARY KEY(id_parametro)
);

CREATE TABLE IF NOT EXISTS tab_dptos
(
    id_dpto  VARCHAR(2)  NOT NULL CHECK (id_dpto ~ '^[0-9]{2}$'),          -- codigo DANE de 2 digitos
    nom_dpto VARCHAR(60) NOT NULL CHECK (BTRIM(nom_dpto) <> ''),
    PRIMARY KEY(id_dpto)
);

CREATE TABLE IF NOT EXISTS tab_ciudades
(
    id_ciudad  VARCHAR(5)  NOT NULL,                -- codigo DANE del municipio
    id_dpto    VARCHAR(2)  NOT NULL,
    nom_ciudad VARCHAR(60) NOT NULL CHECK (BTRIM(nom_ciudad) <> ''),

    PRIMARY KEY(id_ciudad),
    UNIQUE(nom_ciudad, id_dpto),
    CHECK (id_ciudad ~ '^[0-9]{5}$' AND LEFT(id_ciudad, 2) = id_dpto),  -- DANE: el municipio empieza por su departamento
    FOREIGN KEY(id_dpto) REFERENCES tab_dptos(id_dpto)
);
CREATE INDEX IF NOT EXISTS idx_ciudades_dpto ON tab_ciudades(id_dpto);

--*******************************************************************************************
-- PERSONAS, USUARIOS Y SEGURIDAD
--*******************************************************************************************

CREATE TABLE IF NOT EXISTS tab_personas
(
    id_persona     DECIMAL(10,0) NOT NULL CHECK (id_persona > 0),   -- numero de documento
    id_ciudad      VARCHAR(5)    NOT NULL,
    ind_doc        VARCHAR(3)    NOT NULL CHECK (ind_doc IN ('CC','CE','NIT','TI')),
    fec_nacimiento DATE          NULL     CHECK (fec_nacimiento IS NULL OR fec_nacimiento >= DATE '1900-01-01'), -- la edad 16-100 la valida trg_personas_validar
    nom_persona    VARCHAR(100)  NOT NULL CHECK (BTRIM(nom_persona) <> ''),
    apell_persona  VARCHAR(100)  NOT NULL CHECK (BTRIM(apell_persona) <> ''),
    email          VARCHAR(150)  NOT NULL CHECK (email ~* '^[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,}$'),
    num_celular    VARCHAR(10)   NULL     CHECK (num_celular ~ '^3[0-9]{9}$'),  -- celular colombiano: 10 digitos empezando por 3
    deleted_at     TIMESTAMPTZ   NULL,    -- fecha en que se suprimieron sus datos (Ley 1581); NULL = vigente

    PRIMARY KEY(id_persona),
    CHECK (email = LOWER(BTRIM(email))),                                                       -- el correo se guarda en minusculas
    CHECK (deleted_at IS NOT NULL OR (fec_nacimiento IS NOT NULL AND num_celular IS NOT NULL)),  -- solo se vacian si fue suprimida
    FOREIGN KEY(id_ciudad) REFERENCES tab_ciudades(id_ciudad)
);
CREATE UNIQUE INDEX IF NOT EXISTS uix_personas_email ON tab_personas(LOWER(email));   -- un correo = una persona, sin importar mayusculas
CREATE INDEX IF NOT EXISTS idx_personas_ciudad ON tab_personas(id_ciudad);
CREATE INDEX IF NOT EXISTS idx_personas_suprimidas ON tab_personas(deleted_at) WHERE deleted_at IS NOT NULL;

CREATE TABLE IF NOT EXISTS tab_usuarios
(
    id_usuario           DECIMAL(10,0) NOT NULL,             -- la plataforma usa id_usuario = id_persona
    id_persona           DECIMAL(10,0) NOT NULL,
    hash_password        VARCHAR(255)  NOT NULL,             -- solo bcrypt; la plataforma no puede leerla
    ind_activo           BOOLEAN       NOT NULL DEFAULT TRUE,
    ind_email_verificado BOOLEAN       NOT NULL DEFAULT FALSE,
    intentos_fallidos    SMALLINT      NOT NULL DEFAULT 0 CHECK (intentos_fallidos >= 0), -- informativo: el bloqueo lo calcula fun_autenticar
    fec_ultimo_login     TIMESTAMPTZ   NULL,
    fec_creacion         TIMESTAMPTZ   NOT NULL DEFAULT now(),
    fec_actualizacion    TIMESTAMPTZ   NOT NULL DEFAULT now(),

    PRIMARY KEY(id_usuario),
    UNIQUE(id_persona),
    CHECK (hash_password ~ '^\$2[aby]\$[0-9]{2}\$[./A-Za-z0-9]{53}$'          -- bcrypt (PHP o pgcrypto)
        OR hash_password ~ '^(SUPRIMIDO|INVALIDADO)-[0-9a-f]{32}$'),           -- credencial anulada
    FOREIGN KEY(id_persona) REFERENCES tab_personas(id_persona) ON DELETE RESTRICT
);

CREATE TABLE IF NOT EXISTS tab_sesiones
(
    id_sesion      INT GENERATED ALWAYS AS IDENTITY,
    id_usuario     DECIMAL(10,0) NOT NULL,
    token_hash     CHAR(64)      NOT NULL,                   -- SHA-256 del id de sesion de PHP; nunca el valor real
    ip_origen      INET          NULL,
    user_agent     VARCHAR(255)  NULL,                       -- navegador del usuario, para "cerrar otras sesiones"
    ind_activa     BOOLEAN       NOT NULL DEFAULT TRUE,
    fec_inicio     TIMESTAMPTZ   NOT NULL DEFAULT now(),
    fec_expiracion TIMESTAMPTZ   NOT NULL,                   -- vida maxima de la sesion
    fec_ult_uso    TIMESTAMPTZ   NOT NULL DEFAULT now(),     -- para cerrar por inactividad
    fec_cierre     TIMESTAMPTZ   NULL,
    motivo_cierre  VARCHAR(20)   NULL CHECK (motivo_cierre IS NULL OR motivo_cierre IN ('logout','expirada','inactividad','revocada','limite_concurrencia','cambio_clave','supresion')),

    PRIMARY KEY(id_sesion),
    UNIQUE(token_hash),
    CHECK (token_hash ~ '^[0-9a-f]{64}$'),
    CHECK (fec_expiracion > fec_inicio),
    CHECK (fec_cierre IS NULL OR fec_cierre >= fec_inicio),
    CHECK (fec_ult_uso >= fec_inicio),
    CHECK ((ind_activa AND fec_cierre IS NULL AND motivo_cierre IS NULL)              -- activa: sin cierre
        OR (NOT ind_activa AND fec_cierre IS NOT NULL AND motivo_cierre IS NOT NULL)), -- cerrada: con fecha y motivo
    FOREIGN KEY(id_usuario) REFERENCES tab_usuarios(id_usuario) ON DELETE RESTRICT
);
CREATE INDEX IF NOT EXISTS idx_sesiones_usuario  ON tab_sesiones(id_usuario);
CREATE INDEX IF NOT EXISTS idx_sesiones_vigentes ON tab_sesiones(id_usuario, fec_ult_uso DESC) WHERE ind_activa;

-- Tokens de un solo uso: recuperar clave y verificar correo (V1: tab_recuperacion_claves)
CREATE TABLE IF NOT EXISTS tab_tokens_usuario
(
    id_token       INT GENERATED ALWAYS AS IDENTITY,
    id_usuario     DECIMAL(10,0) NOT NULL,
    tipo_token     VARCHAR(20)   NOT NULL CHECK (tipo_token IN ('recuperacion','verificacion_correo')),
    token_hash     CHAR(64)      NOT NULL,                   -- SHA-256; el valor real solo viaja en el correo
    ind_usado      BOOLEAN       NOT NULL DEFAULT FALSE,
    fec_solicitud  TIMESTAMPTZ   NOT NULL DEFAULT now(),
    fec_expiracion TIMESTAMPTZ   NOT NULL,
    fec_uso        TIMESTAMPTZ   NULL,

    PRIMARY KEY(id_token),
    UNIQUE(token_hash),
    CHECK (token_hash ~ '^[0-9a-f]{64}$'),
    CHECK (fec_expiracion > fec_solicitud),
    CHECK (fec_uso IS NULL OR fec_uso >= fec_solicitud),
    CHECK (NOT ind_usado OR fec_uso IS NOT NULL),
    FOREIGN KEY(id_usuario) REFERENCES tab_usuarios(id_usuario) ON DELETE RESTRICT
);
CREATE INDEX IF NOT EXISTS idx_tokens_usuario ON tab_tokens_usuario(id_usuario, tipo_token, fec_solicitud DESC);

-- Bitacora de ingresos. No se modifica ni se borra (trg_append_only).
CREATE TABLE IF NOT EXISTS tab_accesos_auditoria
(
    id_evento               INT GENERATED ALWAYS AS IDENTITY,
    id_usuario              DECIMAL(10,0) NULL,              -- NULL si el usuario escrito no existe
    tipo_evento             VARCHAR(25)   NOT NULL CHECK (tipo_evento IN ('LOGIN_OK','LOGIN_FALLIDO','LOGIN_RECHAZADO','LOGOUT','SESION_EXPIRADA','SESION_RENOVADA','SESION_REVOCADA','TOKEN_EMITIDO','TOKEN_RECHAZADO','CLAVE_CAMBIADA','CLAVE_RESTABLECIDA','CORREO_VERIFICADO','CUENTA_REGISTRADA','CUENTA_SUPRIMIDA')),
    identificador_intentado VARCHAR(150)  NULL,              -- correo o usuario que se escribio en el login
    ip_origen               INET          NULL,
    user_agent              VARCHAR(255)  NULL,
    detalle_evento          VARCHAR(255)  NULL,
    fec_evento              TIMESTAMPTZ   NOT NULL DEFAULT now(),

    PRIMARY KEY(id_evento),
    CHECK (tipo_evento NOT IN ('LOGIN_OK','LOGIN_FALLIDO','LOGIN_RECHAZADO') OR identificador_intentado IS NOT NULL),
    FOREIGN KEY(id_usuario) REFERENCES tab_usuarios(id_usuario) ON DELETE RESTRICT
);
CREATE INDEX IF NOT EXISTS idx_accesos_usuario      ON tab_accesos_auditoria(id_usuario, fec_evento DESC);
CREATE INDEX IF NOT EXISTS idx_accesos_fallos_ident ON tab_accesos_auditoria(identificador_intentado, fec_evento DESC) WHERE tipo_evento IN ('LOGIN_FALLIDO','LOGIN_OK');
CREATE INDEX IF NOT EXISTS idx_accesos_fallos_ip    ON tab_accesos_auditoria(ip_origen, fec_evento DESC) WHERE tipo_evento = 'LOGIN_FALLIDO';
CREATE INDEX IF NOT EXISTS idx_accesos_fecha        ON tab_accesos_auditoria(fec_evento);

-- Reglas de seguridad de la plataforma. Siempre una sola fila (id_parametro = 1).
CREATE TABLE IF NOT EXISTS tab_parametros_seguridad
(
    id_parametro               SMALLINT NOT NULL DEFAULT 1   CHECK (id_parametro = 1),
    long_min_clave             SMALLINT NOT NULL DEFAULT 8   CHECK (long_min_clave BETWEEN 8 AND 64),
    costo_bcrypt               SMALLINT NOT NULL DEFAULT 12  CHECK (costo_bcrypt BETWEEN 10 AND 14),
    max_fallos_identificador   SMALLINT NOT NULL DEFAULT 5   CHECK (max_fallos_identificador > 0),  -- intentos antes de bloquear la cuenta
    max_fallos_ip              SMALLINT NOT NULL DEFAULT 30  CHECK (max_fallos_ip > 0),             -- alto: en Colombia muchos celulares comparten IP
    minutos_ventana_fallos     SMALLINT NOT NULL DEFAULT 15  CHECK (minutos_ventana_fallos > 0),    -- duracion del bloqueo
    minutos_inactividad        SMALLINT NOT NULL DEFAULT 30  CHECK (minutos_inactividad > 0),
    horas_vida_sesion          SMALLINT NOT NULL DEFAULT 12  CHECK (horas_vida_sesion > 0),
    sesiones_concurrentes      SMALLINT NOT NULL DEFAULT 3   CHECK (sesiones_concurrentes > 0),
    minutos_token_recuperacion SMALLINT NOT NULL DEFAULT 30  CHECK (minutos_token_recuperacion > 0),
    horas_token_verificacion   SMALLINT NOT NULL DEFAULT 24  CHECK (horas_token_verificacion > 0),
    max_tokens_hora            SMALLINT NOT NULL DEFAULT 3   CHECK (max_tokens_hora > 0),
    dias_retencion_sesiones    INTEGER  NOT NULL DEFAULT 90  CHECK (dias_retencion_sesiones >= 30),
    dias_retencion_accesos     INTEGER  NOT NULL DEFAULT 180 CHECK (dias_retencion_accesos >= 30),
    dias_retencion_auditoria   INTEGER  NOT NULL DEFAULT 730 CHECK (dias_retencion_auditoria >= 365),

    PRIMARY KEY(id_parametro),
    CHECK (minutos_inactividad <= horas_vida_sesion * 60)
);

-- Roles de la plataforma: solo Agricultor (2) y Tecnico (5)
CREATE TABLE IF NOT EXISTS tab_roles
(
    id_rol      DECIMAL(4,0) NOT NULL,
    nom_rol     VARCHAR(60)  NOT NULL UNIQUE CHECK (BTRIM(nom_rol) <> ''),
    codigo_rol  VARCHAR(20)  NOT NULL UNIQUE,
    descripcion VARCHAR(200) NOT NULL,
    PRIMARY KEY(id_rol),
    CHECK ((id_rol = 2 AND codigo_rol = 'AGRICULTOR') OR (id_rol = 5 AND codigo_rol = 'TECNICO'))
);

CREATE TABLE IF NOT EXISTS tab_permisos
(
    id_permiso     DECIMAL(3,0) NOT NULL CHECK (id_permiso > 0),
    descrip_perm   VARCHAR(160) NOT NULL CHECK (BTRIM(descrip_perm) <> ''),
    codigo_permiso VARCHAR(40)  NOT NULL UNIQUE CHECK (codigo_permiso ~ '^[A-Z][A-Z0-9_]{2,39}$'), -- lo consulta fun_tiene_permiso
    PRIMARY KEY(id_permiso)
);

CREATE TABLE IF NOT EXISTS tab_rol_permisos
(
    id_rol     DECIMAL(4,0) NOT NULL,
    id_permiso DECIMAL(3,0) NOT NULL,
    PRIMARY KEY(id_rol, id_permiso),
    FOREIGN KEY(id_rol)     REFERENCES tab_roles(id_rol),
    FOREIGN KEY(id_permiso) REFERENCES tab_permisos(id_permiso)
);
CREATE INDEX IF NOT EXISTS idx_rol_permisos_permiso ON tab_rol_permisos(id_permiso);

CREATE TABLE IF NOT EXISTS tab_persona_roles
(
    id_persona DECIMAL(10,0) NOT NULL,
    id_rol     DECIMAL(4,0)  NOT NULL,
    PRIMARY KEY(id_persona, id_rol),
    FOREIGN KEY(id_persona) REFERENCES tab_personas(id_persona) ON DELETE RESTRICT,
    FOREIGN KEY(id_rol)     REFERENCES tab_roles(id_rol)
);
CREATE INDEX IF NOT EXISTS idx_persona_roles_rol ON tab_persona_roles(id_rol);

-- Para que se usan los datos personales (Ley 1581 de 2012)
CREATE TABLE IF NOT EXISTS tab_finalidades_tratamiento
(
    id_finalidad    SMALLINT     NOT NULL CHECK (id_finalidad > 0),
    codigo          VARCHAR(30)  NOT NULL UNIQUE CHECK (codigo ~ '^[A-Z][A-Z_]{2,29}$'),
    descripcion     VARCHAR(300) NOT NULL CHECK (BTRIM(descripcion) <> ''),
    ind_obligatoria BOOLEAN      NOT NULL DEFAULT FALSE,   -- TRUE = sin esta autorizacion no se presta el servicio
    estado          BOOLEAN      NOT NULL DEFAULT TRUE,
    PRIMARY KEY(id_finalidad)
);

-- Historial de cambios: quien cambio que y cuando. La llena fun_trg_auditoria; no se modifica ni se borra.
CREATE TABLE IF NOT EXISTS tab_auditoria
(
    id_auditoria  BIGINT GENERATED ALWAYS AS IDENTITY,
    fec_evento    TIMESTAMPTZ   NOT NULL DEFAULT now(),
    id_usuario    DECIMAL(10,0) NULL,                       -- usuario de la plataforma que hizo el cambio
    id_sesion     INT           NULL,
    ip_origen     INET          NULL,                       -- IP desde donde navega el usuario
    usuario_bd    NAME          NOT NULL DEFAULT session_user,
    operacion     VARCHAR(6)    NOT NULL CHECK (operacion IN ('INSERT','UPDATE','DELETE')),
    tabla         VARCHAR(63)   NOT NULL,
    id_registro   VARCHAR(200)  NOT NULL,                   -- llave primaria del registro cambiado
    datos_antes   JSONB         NULL,
    datos_despues JSONB         NULL,

    PRIMARY KEY(id_auditoria),
    CHECK ((operacion = 'INSERT' AND datos_antes IS NULL     AND datos_despues IS NOT NULL)
        OR (operacion = 'DELETE' AND datos_antes IS NOT NULL AND datos_despues IS NULL)
        OR (operacion = 'UPDATE' AND datos_antes IS NOT NULL AND datos_despues IS NOT NULL)),
    -- DEFERRABLE: en el registro de una cuenta nueva el usuario se crea en la misma transaccion
    FOREIGN KEY(id_usuario) REFERENCES tab_usuarios(id_usuario) ON DELETE RESTRICT ON UPDATE RESTRICT DEFERRABLE INITIALLY DEFERRED
);
CREATE INDEX IF NOT EXISTS idx_auditoria_registro ON tab_auditoria(tabla, id_registro);
CREATE INDEX IF NOT EXISTS idx_auditoria_usuario  ON tab_auditoria(id_usuario, fec_evento DESC);
CREATE INDEX IF NOT EXISTS idx_auditoria_fecha    ON tab_auditoria(fec_evento);

-- Historico legible: una fila por cada dato que cambio, con quien y cuando.
-- Ej. historia de una cosecha:
--   SELECT fec_evento, usuario, operacion, campo, valor_antes, valor_despues
--     FROM vw_historial_cambios WHERE tabla = 'tab_cosecha' AND id_registro = '15' ORDER BY fec_evento;
CREATE OR REPLACE VIEW vw_historial_cambios AS
SELECT a.id_auditoria,
       a.fec_evento,
       a.operacion,
       a.tabla,
       a.id_registro,
       c.campo,
       a.datos_antes   ->> c.campo AS valor_antes,
       a.datos_despues ->> c.campo AS valor_despues,
       a.id_usuario,
       TRIM(p.nom_persona || ' ' || p.apell_persona) AS usuario,
       a.ip_origen,
       a.usuario_bd
  FROM tab_auditoria a
 CROSS JOIN LATERAL jsonb_object_keys(COALESCE(a.datos_despues, a.datos_antes)) AS c(campo)
  LEFT JOIN tab_usuarios u ON u.id_usuario = a.id_usuario
  LEFT JOIN tab_personas p ON p.id_persona = u.id_persona
 WHERE a.operacion <> 'UPDATE'                                              -- altas y bajas: todos los datos
    OR a.datos_antes -> c.campo IS DISTINCT FROM a.datos_despues -> c.campo; -- cambios: solo lo que cambio

CREATE TABLE IF NOT EXISTS tab_productor
(
    id_persona    DECIMAL(10,0) NOT NULL, -- PK = FK → tab_personas (relación 1:1)
    tip_productor VARCHAR(10)   NOT NULL CHECK (tip_productor IN ('Pequeño','Mediano','Grande')),
    rend_estimado NUMERIC(12,2) NOT NULL CHECK (rend_estimado >= 0),
    ind_transforma BOOLEAN      NOT NULL, -- ¿Fermenta y seca en finca propia?
    PRIMARY KEY(id_persona),
    FOREIGN KEY(id_persona) REFERENCES tab_personas(id_persona) ON DELETE RESTRICT
);

CREATE TABLE IF NOT EXISTS tab_tecnico
(
    id_persona    DECIMAL(10,0) NOT NULL,
    especialidad  VARCHAR(50)   NOT NULL CHECK (BTRIM(especialidad) <> ''),
    zona_asignada VARCHAR(100)  NOT NULL CHECK (BTRIM(zona_asignada) <> ''),
    vinculo_inst  VARCHAR(20)   NOT NULL  CHECK (vinculo_inst IN ('Fedecacao','Sena','Independiente','Otro')),
    PRIMARY KEY(id_persona),
    FOREIGN KEY(id_persona) REFERENCES tab_personas(id_persona) ON DELETE RESTRICT
);

-- Trabajadores del agricultor: jornaleros, familiares, mano vuelta. No son usuarios ni rol de la
-- plataforma: solo se guarda el nombre, sin cedula, correo ni celular (Ley 1581: no se piden
-- datos de terceros que no hacen falta). Con esto se sabe quien hizo cada labor y cuanto se le paga.
CREATE TABLE IF NOT EXISTS tab_trabajadores
(
    id_trabajador  INT GENERATED ALWAYS AS IDENTITY,
    id_persona     DECIMAL(10,0) NOT NULL,   -- agricultor dueño del listado
    nom_trabajador VARCHAR(120)  NOT NULL CHECK (BTRIM(nom_trabajador) <> ''),
    estado         BOOLEAN       NOT NULL DEFAULT TRUE,   -- FALSE = ya no trabaja con el agricultor (no se borra: tiene historia)
    PRIMARY KEY(id_trabajador),
    UNIQUE(id_trabajador, id_persona),       -- lo usa la FK de tab_jornales: el jornal es del mismo agricultor
    FOREIGN KEY(id_persona) REFERENCES tab_personas(id_persona) ON DELETE RESTRICT
);
CREATE UNIQUE INDEX IF NOT EXISTS uix_trabajador_nombre ON tab_trabajadores(id_persona, LOWER(BTRIM(nom_trabajador)));  -- "Juan" y "juan " son el mismo

--*******************************************************************************************
-- FINCA
--*******************************************************************************************

CREATE TABLE IF NOT EXISTS tab_finca
(
    id_finca      VARCHAR(30)   NOT NULL CHECK (BTRIM(id_finca) <> ''),
    id_ciudad     VARCHAR(5)    NOT NULL,
    id_persona    DECIMAL(10,0) NOT NULL,                    -- agricultor titular de la finca
    num_catast    VARCHAR(40)   NOT NULL CHECK (BTRIM(num_catast) <> ''),
    nom_finca     VARCHAR(120)  NOT NULL CHECK (BTRIM(nom_finca) <> ''),
    hect_ttl      DECIMAL(10,2) NOT NULL CHECK (hect_ttl > 0),     -- V2: admite 2,5 ha
    hect_cacao    DECIMAL(10,2) NOT NULL CHECK (hect_cacao >= 0),
    val_lati      DECIMAL(11,8) NOT NULL CHECK (val_lati  BETWEEN -4.5  AND 16.5),   -- dentro de Colombia (incluye San Andres):
    val_long      DECIMAL(11,8) NOT NULL CHECK (val_long  BETWEEN -82.5 AND -66.5),  -- atrapa latitud y longitud invertidas
    altitud_msnm  DECIMAL(5,0)  CHECK (altitud_msnm BETWEEN 0 AND 5000),
    nom_vereda    VARCHAR(100),
    zona_agroecol VARCHAR(30)   CHECK (zona_agroecol IN ('Baja','Media','Alta')), -- Baja: 0-800 msnm · Media: 800-1200 msnm · Alta: >1200 msnm
    estado        BOOLEAN       NOT NULL DEFAULT TRUE,       -- FALSE = finca retirada (no se borra porque tiene historia)

    PRIMARY KEY(id_finca),
    UNIQUE(num_catast),
    CHECK (hect_cacao <= hect_ttl),
    CHECK (zona_agroecol IS NULL OR altitud_msnm IS NULL                         -- la zona corresponde a la altitud
        OR (zona_agroecol = 'Baja'  AND altitud_msnm <= 800)
        OR (zona_agroecol = 'Media' AND altitud_msnm BETWEEN 800 AND 1200)
        OR (zona_agroecol = 'Alta'  AND altitud_msnm > 1200)),
    FOREIGN KEY(id_ciudad)  REFERENCES tab_ciudades(id_ciudad),
    FOREIGN KEY(id_persona) REFERENCES tab_personas(id_persona) ON DELETE RESTRICT
);
CREATE INDEX IF NOT EXISTS idx_finca_ciudad  ON tab_finca(id_ciudad);
CREATE INDEX IF NOT EXISTS idx_finca_persona ON tab_finca(id_persona);

CREATE TABLE IF NOT EXISTS tab_catalogo_variedad
(
    id_variedad   DECIMAL(4,0)  NOT NULL CHECK (id_variedad > 0),
    nombre_vari   VARCHAR(80)   NOT NULL UNIQUE CHECK (BTRIM(nombre_vari) <> ''),
    descrip_cacao VARCHAR(300)  NOT NULL CHECK (BTRIM(descrip_cacao) <> ''),
    tipo_cacao    VARCHAR(20)   NOT NULL CHECK (tipo_cacao IN ('Criollo','Forastero','Trinitario','CCN-51','Hibrido')),
    ind_aroma     VARCHAR(60)   NOT NULL CHECK (BTRIM(ind_aroma) <> ''),
    ind_sabor     VARCHAR(60)   NOT NULL CHECK (BTRIM(ind_sabor) <> ''),
    ind_tamano    VARCHAR(60)   NOT NULL CHECK (BTRIM(ind_tamano) <> ''),
    rend_promedio DECIMAL(10,2) CHECK (rend_promedio IS NULL OR rend_promedio >= 0),
    estado        BOOLEAN       NOT NULL DEFAULT TRUE,
    PRIMARY KEY(id_variedad)
);

CREATE TABLE IF NOT EXISTS tab_finca_variedad
(
    id_finca        VARCHAR(30)   NOT NULL,
    id_variedad     DECIMAL(4,0)  NOT NULL,
    rend_cacao      DECIMAL(10,2) NOT NULL CHECK (rend_cacao >= 0),
    num_plantas     DECIMAL(8,0)  CHECK (num_plantas IS NULL OR num_plantas >= 0),
    estado_cacao    BOOLEAN       NOT NULL DEFAULT TRUE, -- TRUE=activo, FALSE=erradicado o muerto
    fec_siembra_ini DATE          CHECK (fec_siembra_ini >= DATE '1950-01-01'),
    PRIMARY KEY(id_finca, id_variedad),
    FOREIGN KEY(id_finca)    REFERENCES tab_finca(id_finca),
    FOREIGN KEY(id_variedad) REFERENCES tab_catalogo_variedad(id_variedad)
);
CREATE INDEX IF NOT EXISTS idx_finca_variedad_variedad ON tab_finca_variedad(id_variedad);

-- Otras personas vinculadas a la finca. 'Tecnico' es lo que le da al tecnico acceso a la finca.
-- El titular no se repite aqui: ya esta en tab_finca.id_persona.
CREATE TABLE IF NOT EXISTS tab_fincas_personas
(
    id_finca    VARCHAR(30)   NOT NULL,
    id_persona  DECIMAL(10,0) NOT NULL,
    tip_rela    VARCHAR(15)   NOT NULL CHECK (tip_rela IN ('Arrendatario','Propietario','Administrador','Aparcero','Tecnico')),
    fech_inicio DATE          NOT NULL CHECK (fech_inicio >= DATE '1950-01-01'),
    fech_fin    DATE          NULL,      -- NULL = vinculo vigente
    PRIMARY KEY(id_finca, id_persona, fech_inicio),  -- con fech_inicio se puede volver a vincular a la misma persona
    CHECK (fech_fin IS NULL OR fech_fin >= fech_inicio),
    FOREIGN KEY(id_finca)   REFERENCES tab_finca(id_finca),
    FOREIGN KEY(id_persona) REFERENCES tab_personas(id_persona) ON DELETE RESTRICT
);
CREATE UNIQUE INDEX IF NOT EXISTS uix_fincas_personas_abierta ON tab_fincas_personas(id_finca, id_persona) WHERE fech_fin IS NULL;
CREATE INDEX IF NOT EXISTS idx_fincas_personas_persona ON tab_fincas_personas(id_persona);

--*******************************************************************************************
-- CATALOGOS NUEVOS
--*******************************************************************************************

-- factor_base convierte a kg (Masa) o a litros (Volumen)
CREATE TABLE IF NOT EXISTS tab_unidad_medida
(
    id_unidad   SMALLINT GENERATED ALWAYS AS IDENTITY,
    sigla       VARCHAR(10)   NOT NULL CHECK (BTRIM(sigla) <> ''),
    nom_unidad  VARCHAR(40)   NOT NULL CHECK (BTRIM(nom_unidad) <> ''),
    magnitud    VARCHAR(10)   NOT NULL CHECK (magnitud IN ('Masa','Volumen','Unidad')),
    factor_base NUMERIC(14,8) NULL     CHECK (factor_base IS NULL OR factor_base > 0),
    PRIMARY KEY(id_unidad),
    CHECK (magnitud = 'Unidad' OR factor_base IS NOT NULL)
);
CREATE UNIQUE INDEX IF NOT EXISTS uix_unidad_sigla ON tab_unidad_medida(LOWER(sigla));

-- V1 guardaba la herramienta como texto libre en actividades y cosecha
CREATE TABLE IF NOT EXISTS tab_catalogo_herramienta
(
    id_herramienta  SMALLINT GENERATED ALWAYS AS IDENTITY,
    nom_herramienta VARCHAR(60) NOT NULL CHECK (BTRIM(nom_herramienta) <> ''),
    estado          BOOLEAN     NOT NULL DEFAULT TRUE,
    PRIMARY KEY(id_herramienta)
);
CREATE UNIQUE INDEX IF NOT EXISTS uix_herramienta_nombre ON tab_catalogo_herramienta(LOWER(BTRIM(nom_herramienta)));

-- Un solo listado de calidades para cosecha y analisis de calidad (V1 tenia dos)
CREATE TABLE IF NOT EXISTS tab_catalogo_calidad_cacao
(
    id_calidad  SMALLINT GENERATED ALWAYS AS IDENTITY,
    nom_calidad VARCHAR(40)  NOT NULL CHECK (BTRIM(nom_calidad) <> ''),
    descripcion VARCHAR(200) NULL,
    estado      BOOLEAN      NOT NULL DEFAULT TRUE,
    PRIMARY KEY(id_calidad)
);
CREATE UNIQUE INDEX IF NOT EXISTS uix_calidad_nombre ON tab_catalogo_calidad_cacao(LOWER(BTRIM(nom_calidad)));

--*******************************************************************************************
-- LOTES Y ACTIVIDADES
--*******************************************************************************************

CREATE TABLE IF NOT EXISTS tab_lotes
(
    id_lote        DECIMAL(10,0)  NOT NULL CHECK (id_lote > 0),
    id_finca       VARCHAR(30)    NOT NULL,
    nom_lote       VARCHAR(100)   NOT NULL CHECK (BTRIM(nom_lote) <> ''),
    area_hecta     DECIMAL(10,2)  NOT NULL CHECK (area_hecta > 0),
    ph_suelo       DECIMAL(4,2)   NULL CHECK (ph_suelo BETWEEN 0 AND 14),  -- V2: opcional; el pH oficial es el de tab_analisis_suelo
    val_latitud    DECIMAL(11,8)  NOT NULL CHECK (val_latitud BETWEEN -4.5 AND 16.5),    -- dentro de Colombia
    val_longitud   DECIMAL(11,8)  NOT NULL CHECK (val_longitud BETWEEN -82.5 AND -66.5),
    altitud_msnm   DECIMAL(5,0)   NULL CHECK (altitud_msnm BETWEEN 0 AND 5000),
    estado_general BOOLEAN        NOT NULL  DEFAULT TRUE, -- TRUE = disponible, FALSE = no apto
    fecha_registro DATE           NOT NULL DEFAULT CURRENT_DATE CHECK (fecha_registro >= DATE '1950-01-01'),
    observaciones  TEXT           NULL,
    PRIMARY KEY(id_lote),
    UNIQUE(id_finca, nom_lote), -- Evita dos lotes con el mismo nombre en una misma finca
    FOREIGN KEY(id_finca) REFERENCES tab_finca(id_finca) ON DELETE RESTRICT
);

CREATE TABLE IF NOT EXISTS tab_actividades
(
    id_actividad      INT GENERATED ALWAYS AS IDENTITY,
    id_persona        DECIMAL(10,0) NOT NULL,     -- quien la registra o programa: agricultor o tecnico
    id_trabajador     INT           NULL,         -- quien hizo la labor; NULL = la hizo quien la registra
    id_lote           DECIMAL(10,0) NULL,         -- V2: el lote como llave (reemplaza a lote_desc)
    lote_desc         VARCHAR(150)  NULL,         -- DEPRECADA: texto "Finca - Lote"; se quita cuando la plataforma envie id_lote
    nom_actividad     VARCHAR(120)  NOT NULL CHECK (BTRIM(nom_actividad) <> ''),
    id_herramienta    SMALLINT      NULL,
    fech_inicio       DATE          NOT NULL CHECK (fech_inicio >= DATE '1950-01-01'),
    fech_fin          DATE          NOT  NULL,
    CHECK (fech_fin >= fech_inicio),
    PRIMARY KEY(id_actividad),
    FOREIGN KEY(id_persona)     REFERENCES tab_personas(id_persona) ON DELETE RESTRICT,
    FOREIGN KEY(id_trabajador)  REFERENCES tab_trabajadores(id_trabajador) ON DELETE RESTRICT,
    FOREIGN KEY(id_lote)        REFERENCES tab_lotes(id_lote) ON DELETE RESTRICT,
    FOREIGN KEY(id_herramienta) REFERENCES tab_catalogo_herramienta(id_herramienta) ON DELETE RESTRICT
);
CREATE INDEX IF NOT EXISTS idx_actividades_persona     ON tab_actividades(id_persona, fech_inicio DESC);
CREATE INDEX IF NOT EXISTS idx_actividades_trabajador  ON tab_actividades(id_trabajador);
CREATE INDEX IF NOT EXISTS idx_actividades_lote        ON tab_actividades(id_lote);
CREATE INDEX IF NOT EXISTS idx_actividades_herramienta ON tab_actividades(id_herramienta);

CREATE TABLE IF NOT EXISTS tab_calendario_agricola
(
    id_calendario    INT GENERATED ALWAYS AS IDENTITY,
    id_actividad     INT NOT NULL,
    estado_actividad SMALLINT      NOT NULL CHECK (estado_actividad  >=0 AND estado_actividad <= 2),--'Pendiente','Completada','Retrasada'
    descripcion      VARCHAR(255)  NOT NULL CHECK (BTRIM(descripcion) <> ''),
    PRIMARY KEY(id_calendario),
    FOREIGN KEY(id_actividad) REFERENCES tab_actividades(id_actividad)
);
CREATE INDEX IF NOT EXISTS idx_calendario_actividad ON tab_calendario_agricola(id_actividad);

CREATE TABLE IF NOT EXISTS tab_preparacion_lotes
(
    id_preparacion    INT GENERATED ALWAYS AS IDENTITY,
    id_lote           DECIMAL(10,0) NOT NULL,
    id_persona        DECIMAL(10,0) NOT NULL,     -- quien la registra: agricultor o tecnico (V1 exigia un operario)
    id_trabajador     INT           NULL,         -- quien hizo la labor; NULL = la hizo quien la registra
    fecha_evaluacion  DATE          NOT NULL DEFAULT CURRENT_DATE CHECK (fecha_evaluacion >= DATE '1950-01-01'),
    punto_muestreo    VARCHAR(20)   NULL,     -- Zonas físicas ('P1', 'P2')
    profundidad_cm    DECIMAL(4,0)  NULL CHECK (profundidad_cm BETWEEN 0 AND 100),
    metodo_preparacion VARCHAR(100) NULL,     -- Tipo de arado o maquinaria usada
    tipo_abono_inicial VARCHAR(100) NULL,     -- Abono usado en la preparación
    observaciones     TEXT          NULL,

    PRIMARY KEY(id_preparacion),
    FOREIGN KEY(id_persona)    REFERENCES tab_personas(id_persona) ON DELETE RESTRICT,
    FOREIGN KEY(id_trabajador) REFERENCES tab_trabajadores(id_trabajador) ON DELETE RESTRICT,
    FOREIGN KEY(id_lote)       REFERENCES tab_lotes(id_lote)
);
CREATE INDEX IF NOT EXISTS idx_preparacion_lote       ON tab_preparacion_lotes(id_lote);
CREATE INDEX IF NOT EXISTS idx_preparacion_persona    ON tab_preparacion_lotes(id_persona);
CREATE INDEX IF NOT EXISTS idx_preparacion_trabajador ON tab_preparacion_lotes(id_trabajador);

CREATE TABLE IF NOT EXISTS tab_analisis_suelo
(
    id_analisis        INT GENERATED ALWAYS AS IDENTITY,
    id_preparacion     INT           NOT NULL, -- Conectado directo a la preparación que evalúa
    fecha_analisis     DATE          NOT NULL DEFAULT CURRENT_DATE CHECK (fecha_analisis >= DATE '1950-01-01'),
    laboratorio        VARCHAR(100)  NULL,
    ph_suelo           DECIMAL(4,2)  NOT NULL CHECK (ph_suelo BETWEEN 0 AND 14),
    materia_organica   DECIMAL(5,2)  NOT NULL CHECK (materia_organica BETWEEN 0 AND 100),  -- porcentaje
    conductividad      DECIMAL(5,2)  NULL CHECK (conductividad >= 0),
    textura_detallada  VARCHAR(30)   NULL,
    fosforo_ppm        DECIMAL(8,2)  NULL CHECK (fosforo_ppm >= 0),
    potasio_meq        DECIMAL(8,2)  NULL CHECK (potasio_meq >= 0),
    calcio_meq         DECIMAL(8,2)  NULL CHECK (calcio_meq >= 0),
    magnesio_meq       DECIMAL(8,2)  NULL CHECK (magnesio_meq >= 0),
    cadmio_ppm         DECIMAL(10,4) NULL,     -- V2: 4 decimales, el cadmio se mide en milesimas de ppm
    plomo_ppm          DECIMAL(10,4) NULL,
    zinc_ppm           DECIMAL(8,2)  NULL CHECK (zinc_ppm >= 0),
    cobre_ppm          DECIMAL(8,2)  NULL CHECK (cobre_ppm >= 0),
    estado_aprobacion  VARCHAR(30)   NOT NULL DEFAULT 'Pendiente' CHECK (estado_aprobacion IN ('Pendiente','Requiere_Correccion','Apto_para_siembra','No_Apto')),
    recomendaciones    TEXT          NULL,
    fecha_listo        DATE          NULL,

    PRIMARY KEY(id_analisis),
    CHECK ((cadmio_ppm IS NULL OR cadmio_ppm >= 0) AND (plomo_ppm IS NULL OR plomo_ppm >= 0)),
    CHECK (fecha_listo IS NULL OR fecha_listo >= fecha_analisis),
    CONSTRAINT fk_analisis_prep FOREIGN KEY(id_preparacion) REFERENCES tab_preparacion_lotes(id_preparacion) ON DELETE RESTRICT ON UPDATE RESTRICT
);
CREATE INDEX IF NOT EXISTS idx_analisis_suelo_prep ON tab_analisis_suelo(id_preparacion);

CREATE TABLE IF NOT EXISTS tab_lote_productivo
(
    id_lot_prod       INT GENERATED ALWAYS AS IDENTITY,
    id_analisis       INT           NOT NULL, -- <--- Conexión al análisis químico que dio el OK
    id_variedad       DECIMAL(4,0)  NOT NULL,
    fecha_plantacion  DATE          NOT NULL CHECK (fecha_plantacion >= DATE '1950-01-01'),
    estado_prod       VARCHAR(20)   NOT NULL DEFAULT 'En_desarrollo'
        CHECK (estado_prod IN ('En_desarrollo', 'Productivo', 'En_renovacion', 'Erradicado')),

    PRIMARY KEY(id_lot_prod),
    CONSTRAINT fk_prod_analisis FOREIGN KEY(id_analisis) REFERENCES tab_analisis_suelo(id_analisis) ON DELETE RESTRICT ON UPDATE RESTRICT,
    CONSTRAINT fk_prod_variedad FOREIGN KEY(id_variedad) REFERENCES tab_catalogo_variedad(id_variedad) ON DELETE RESTRICT ON UPDATE RESTRICT
);
CREATE INDEX IF NOT EXISTS idx_lote_prod_analisis ON tab_lote_productivo(id_analisis);
CREATE INDEX IF NOT EXISTS idx_lote_prod_variedad ON tab_lote_productivo(id_variedad);

CREATE TABLE IF NOT EXISTS tab_activ_lote
(
    id_actividad        INT NOT NULL,
    id_lot_prod         INT NOT NULL,
    PRIMARY KEY(id_actividad,id_lot_prod),
    FOREIGN KEY(id_actividad) REFERENCES tab_actividades(id_actividad),
    FOREIGN KEY(id_lot_prod ) REFERENCES tab_lote_productivo(id_lot_prod)
);
CREATE INDEX IF NOT EXISTS idx_activ_lote_lote_prod ON tab_activ_lote(id_lot_prod);

CREATE TABLE IF NOT EXISTS tab_siembra
(
    id_siembra          INT GENERATED ALWAYS AS IDENTITY,
    id_actividad        INT NOT NULL,
    cant_planta         DECIMAL(8,0)  NOT NULL CHECK (cant_planta > 0),
    fech_inicio         DATE          NOT NULL CHECK (fech_inicio >= DATE '1950-01-01'),
    fech_fin            DATE          NOT NULL CHECK (fech_fin >= fech_inicio),
    PRIMARY KEY(id_siembra),
    UNIQUE(id_actividad),                         -- una siembra por actividad
    FOREIGN KEY(id_actividad) REFERENCES tab_actividades(id_actividad) ON DELETE RESTRICT
);

--ESTA TABLA ES NETAMENTE PARA EL MONITOREO DE LA SIEMBRA, NO PARA OTRAS ACTIVIDADES (CUANDO SE TRASPLANTA LA PLÁNTULA)
CREATE TABLE IF NOT EXISTS tab_monitoreo_siembra
(
    id_monit_siemb INT GENERATED ALWAYS AS IDENTITY,
    id_siembra     INT NOT NULL,
    fech_inspec    DATE          NOT NULL CHECK (fech_inspec >= DATE '1950-01-01'),
    plant_perdid   DECIMAL(8,0)  NOT NULL CHECK (plant_perdid >= 0),
    plant_enferm   DECIMAL(8,0)  NOT NULL CHECK (plant_enferm >= 0),
    nivel_afec     VARCHAR(20)   NOT NULL CHECK (nivel_afec IN ('Bajo','Medio','Alto')),
    tratamiento    VARCHAR(200)  NOT NULL CHECK (BTRIM(tratamiento) <> ''),
    PRIMARY KEY(id_monit_siemb),
    FOREIGN KEY(id_siembra) REFERENCES tab_siembra(id_siembra)
);
CREATE INDEX IF NOT EXISTS idx_monitoreo_siembra_siem ON tab_monitoreo_siembra(id_siembra);

CREATE TABLE IF NOT EXISTS tab_alertas_enviadas
(
    id_alerta     INT GENERATED ALWAYS AS IDENTITY,
    id_calendario INT NOT NULL,
    fec_envio     TIMESTAMPTZ   NOT NULL DEFAULT CURRENT_TIMESTAMP,
    medio_envio   VARCHAR(20)   NOT NULL CHECK (medio_envio IN ('Email','SMS','Web')),  -- V2: 'Web' en lugar de 'App'
    estado_envio  VARCHAR(20)   NOT NULL CHECK (estado_envio IN ('Enviado','Entregado','Fallido')),
    mensaje       VARCHAR(255)  NOT NULL CHECK (BTRIM(mensaje) <> ''),
    PRIMARY KEY(id_alerta),
    FOREIGN KEY(id_calendario) REFERENCES tab_calendario_agricola(id_calendario)
);
CREATE INDEX IF NOT EXISTS idx_alertas_env_calendario ON tab_alertas_enviadas(id_calendario);

--Declaramos la meta de lo que esperamos producir anualmente
CREATE TABLE IF NOT EXISTS tab_meta_produccion
(
    id_meta         INT GENERATED ALWAYS AS IDENTITY,
    id_finca        VARCHAR(30)   NOT NULL,
    anio            SMALLINT      NOT NULL CHECK (anio BETWEEN 2000 AND 2200),
    periodo         VARCHAR(10)   NOT NULL CHECK (periodo IN ('Anual','Semestre1','Semestre2','Q1','Q2','Q3','Q4')),
    id_variedad     DECIMAL(4,0)  NULL, -- NULL = meta global; valor = meta por variedad
    cant_kg_meta    NUMERIC(14,2) NOT NULL CHECK (cant_kg_meta > 0),
    observaciones   TEXT          NULL,
    PRIMARY KEY (id_meta),
    FOREIGN KEY (id_finca)    REFERENCES tab_finca(id_finca),
    FOREIGN KEY (id_variedad) REFERENCES tab_catalogo_variedad(id_variedad)
);
CREATE UNIQUE INDEX IF NOT EXISTS idx_meta_prod_global
    ON tab_meta_produccion (id_finca, anio, periodo)
    WHERE id_variedad IS NULL;
CREATE UNIQUE INDEX IF NOT EXISTS idx_meta_prod_variedad
    ON tab_meta_produccion (id_finca, anio, periodo, id_variedad)
    WHERE id_variedad IS NOT NULL;
CREATE INDEX IF NOT EXISTS idx_meta_prod_finca           ON tab_meta_produccion(id_finca);
CREATE INDEX IF NOT EXISTS idx_meta_produccion_variedad  ON tab_meta_produccion(id_variedad);

--*******************************************************************************************
-- COSECHA
--*******************************************************************************************

CREATE TABLE IF NOT EXISTS tab_cosecha
(
    id_cosecha       INT GENERATED ALWAYS AS IDENTITY,
    id_persona       DECIMAL(10,0) NOT NULL,     -- quien la registra: agricultor o tecnico (V1 exigia un operario)
    id_trabajador    INT           NULL,         -- quien cosecho; NULL = lo hizo quien la registra
    id_lot_prod      INT NOT NULL,
    fech_cosecha     DATE          NOT NULL CHECK (fech_cosecha >= DATE '1950-01-01'),
    id_calidad       SMALLINT      NULL,         -- V2: catalogo (V1: texto libre calidad_cacao)
    id_herramienta   SMALLINT      NULL,         -- V2: catalogo (V1: texto libre)
    estado_beneficio VARCHAR(20)   NOT NULL DEFAULT 'Baba' CHECK (estado_beneficio IN ('Baba','Fermentado','Seco')), -- sin 'Tostado': fuera de alcance
    peso_kg          NUMERIC(12,2) NOT NULL CHECK (peso_kg > 0),  -- siempre en kg (V1 podia tener arrobas aqui)
    observaciones    TEXT          NULL,         -- V2: el clima va en tab_registro_climatico
    PRIMARY KEY(id_cosecha),
    FOREIGN KEY(id_persona)     REFERENCES tab_personas(id_persona) ON DELETE RESTRICT,
    FOREIGN KEY(id_trabajador)  REFERENCES tab_trabajadores(id_trabajador) ON DELETE RESTRICT,
    FOREIGN KEY(id_lot_prod)    REFERENCES tab_lote_productivo(id_lot_prod),
    FOREIGN KEY(id_calidad)     REFERENCES tab_catalogo_calidad_cacao(id_calidad) ON DELETE RESTRICT,
    FOREIGN KEY(id_herramienta) REFERENCES tab_catalogo_herramienta(id_herramienta) ON DELETE RESTRICT
);
CREATE INDEX IF NOT EXISTS idx_cosecha_persona     ON tab_cosecha(id_persona);
CREATE INDEX IF NOT EXISTS idx_cosecha_trabajador  ON tab_cosecha(id_trabajador);
CREATE INDEX IF NOT EXISTS idx_cosecha_lote_prod   ON tab_cosecha(id_lot_prod, fech_cosecha DESC);
CREATE INDEX IF NOT EXISTS idx_cosecha_calidad     ON tab_cosecha(id_calidad);
CREATE INDEX IF NOT EXISTS idx_cosecha_herramienta ON tab_cosecha(id_herramienta);

--*******************************************************************************************
--SECCIÓN PARA EL CONTROL DE PLAGAS
--*******************************************************************************************
CREATE TABLE IF NOT EXISTS tab_catalogo_plaga
 (
    id_plaga        SMALLINT     NOT NULL CHECK (id_plaga > 0),
    nom_plaga       VARCHAR(100) NOT NULL UNIQUE CHECK (BTRIM(nom_plaga) <> ''),
    tip_agente      VARCHAR(20)  NOT NULL CHECK (tip_agente IN ('Hongo','Bacteria','Insecto','Acaro','Virus','Otro')),
    parte_afectada  VARCHAR(50)  NOT NULL CHECK (BTRIM(parte_afectada) <> ''),
    descripcion     TEXT         NULL,
    estado          BOOLEAN      NOT NULL DEFAULT TRUE,
    PRIMARY KEY (id_plaga)
);

-- V2: ya no tiene id_actividad (un catalogo no depende de una actividad); va en tab_tratamiento_aplicado
CREATE TABLE IF NOT EXISTS tab_catalogo_tratamiento
(
    id_tratamiento        SMALLINT     NOT NULL CHECK (id_tratamiento > 0),
    nom_tratamiento       VARCHAR(100) NOT NULL CHECK (BTRIM(nom_tratamiento) <> ''),
    tip_tratamiento       VARCHAR(20)  NOT NULL CHECK (tip_tratamiento IN ('Quimico','Biologico','Cultural','Mecanico')),
    descripcion           TEXT         NOT NULL CHECK (BTRIM(descripcion) <> ''),
    periodo_carencia_dias DECIMAL(3,0) NULL CHECK (periodo_carencia_dias IS NULL OR periodo_carencia_dias >= 0),
    estado                BOOLEAN      NOT NULL DEFAULT TRUE,
    PRIMARY KEY (id_tratamiento)
);
CREATE UNIQUE INDEX IF NOT EXISTS uix_tratamiento_nombre ON tab_catalogo_tratamiento(LOWER(BTRIM(nom_tratamiento)));

-- V2: tab_insumos de V1 se divide en dos: el producto (catalogo) y cada vez que se aplica
CREATE TABLE IF NOT EXISTS tab_catalogo_insumo
(
    id_insumo             INT GENERATED ALWAYS AS IDENTITY,
    nom_insumo            VARCHAR(100)  NOT NULL CHECK (BTRIM(nom_insumo) <> ''),
    tip_insumo            VARCHAR(20)   NOT NULL CHECK (tip_insumo IN ('Fertilizante','Fungicida','Insecticida','Herbicida','Enmienda','Bioinsumo','Semilla','Otro')),
    id_unidad             SMALLINT      NOT NULL,
    reg_ica               VARCHAR(30)   NULL CHECK (reg_ica IS NULL OR BTRIM(reg_ica) NOT IN ('', '0')), -- NULL = no aplica (V1 usaba '0')
    periodo_carencia_dias DECIMAL(3,0)  NULL CHECK (periodo_carencia_dias IS NULL OR periodo_carencia_dias >= 0),
    costo_referencia      NUMERIC(12,2) NOT NULL DEFAULT 0 CHECK (costo_referencia >= 0),
    estado                BOOLEAN       NOT NULL DEFAULT TRUE,
    PRIMARY KEY(id_insumo),
    FOREIGN KEY(id_unidad) REFERENCES tab_unidad_medida(id_unidad) ON DELETE RESTRICT ON UPDATE RESTRICT
);
CREATE UNIQUE INDEX IF NOT EXISTS uix_catalogo_insumo_nombre ON tab_catalogo_insumo(LOWER(BTRIM(nom_insumo)));
CREATE INDEX IF NOT EXISTS idx_catalogo_insumo_unidad ON tab_catalogo_insumo(id_unidad);

CREATE TABLE IF NOT EXISTS tab_aplicacion_insumo
(
    id_aplicacion  INT GENERATED ALWAYS AS IDENTITY,
    id_insumo      INT           NOT NULL,
    id_actividad   INT           NOT NULL,
    id_lot_prod    INT           NULL,
    fec_aplicacion DATE          NOT NULL DEFAULT CURRENT_DATE CHECK (fec_aplicacion >= DATE '1950-01-01'),
    cantidad       NUMERIC(12,3) NOT NULL CHECK (cantidad > 0),
    id_unidad      SMALLINT      NOT NULL,
    costo_unitario NUMERIC(12,2) NOT NULL DEFAULT 0 CHECK (costo_unitario >= 0),
    costo_total    NUMERIC(16,2) GENERATED ALWAYS AS (ROUND(cantidad * costo_unitario, 2)) STORED, -- se calcula solo
    dosis          VARCHAR(60)   NULL CHECK (BTRIM(dosis) <> ''),
    interv_apli    DECIMAL(1,0)  NULL CHECK (interv_apli IS NULL OR interv_apli >= 0),
    observaciones  TEXT          NULL,
    PRIMARY KEY(id_aplicacion),
    FOREIGN KEY(id_insumo)    REFERENCES tab_catalogo_insumo(id_insumo)     ON DELETE RESTRICT ON UPDATE RESTRICT,
    FOREIGN KEY(id_actividad) REFERENCES tab_actividades(id_actividad)      ON DELETE RESTRICT ON UPDATE RESTRICT,
    FOREIGN KEY(id_lot_prod)  REFERENCES tab_lote_productivo(id_lot_prod)   ON DELETE RESTRICT ON UPDATE RESTRICT,
    FOREIGN KEY(id_unidad)    REFERENCES tab_unidad_medida(id_unidad)       ON DELETE RESTRICT ON UPDATE RESTRICT
);
CREATE INDEX IF NOT EXISTS idx_aplic_insumo_insumo    ON tab_aplicacion_insumo(id_insumo);
CREATE INDEX IF NOT EXISTS idx_aplic_insumo_actividad ON tab_aplicacion_insumo(id_actividad);
CREATE INDEX IF NOT EXISTS idx_aplic_insumo_lote_prod ON tab_aplicacion_insumo(id_lot_prod);
CREATE INDEX IF NOT EXISTS idx_aplic_insumo_unidad    ON tab_aplicacion_insumo(id_unidad);

-- V2: el monitoreo cuelga del lote productivo (V1 lo colgaba de la cosecha: no se podia monitorear antes de cosechar)
CREATE TABLE IF NOT EXISTS tab_monitoreo_periodico
(
    id_monit_period INT GENERATED ALWAYS AS IDENTITY,
    id_lot_prod     INT NOT NULL,
    id_persona      DECIMAL(10,0) NOT NULL,   -- quien lo registra: agricultor o tecnico
    id_trabajador   INT           NULL,       -- quien hizo el recorrido; NULL = lo hizo quien lo registra
    fech_inspec     DATE          NOT NULL CHECK (fech_inspec >= DATE '1950-01-01'),
    ind_incidencia  BOOLEAN       NOT NULL DEFAULT FALSE,
    observaciones   TEXT          NULL,
    PRIMARY KEY(id_monit_period),
    FOREIGN KEY(id_lot_prod)   REFERENCES tab_lote_productivo(id_lot_prod) ON DELETE RESTRICT ON UPDATE RESTRICT,
    FOREIGN KEY(id_persona)    REFERENCES tab_personas(id_persona) ON DELETE RESTRICT,
    FOREIGN KEY(id_trabajador) REFERENCES tab_trabajadores(id_trabajador) ON DELETE RESTRICT
);
CREATE INDEX IF NOT EXISTS idx_monitoreo_lote_prod   ON tab_monitoreo_periodico(id_lot_prod, fech_inspec DESC);
CREATE INDEX IF NOT EXISTS idx_monitoreo_persona     ON tab_monitoreo_periodico(id_persona);
CREATE INDEX IF NOT EXISTS idx_monitoreo_trabajador  ON tab_monitoreo_periodico(id_trabajador);

CREATE TABLE IF NOT EXISTS tab_incidencia_sanitaria
(
    id_incidencia   INT GENERATED ALWAYS AS IDENTITY,
    id_lot_prod     INT NOT NULL,
    id_monit_period INT NULL,                 -- V2: opcional, puede detectarse fuera de un monitoreo
    id_plaga        SMALLINT      NOT NULL,
    id_persona      DECIMAL(10,0) NOT NULL,   -- quien la registra: agricultor o tecnico
    id_trabajador   INT           NULL,       -- quien la detecto en campo; NULL = la detecto quien la registra
    fec_deteccion   DATE          NOT NULL DEFAULT CURRENT_DATE CHECK (fec_deteccion >= DATE '1950-01-01'),
    nivel_afec      VARCHAR(20)   NOT NULL CHECK (nivel_afec IN ('Leve','Moderado','Severo','Critico')),
    cant_plantas_afec NUMERIC(10,0) NULL CHECK (cant_plantas_afec >= 0),  -- numero de plantas
    estado          VARCHAR(20)   NOT NULL DEFAULT 'activa' CHECK (estado IN ('activa','controlada','reincidente','cerrada')),
    observaciones   TEXT          NULL,
    PRIMARY KEY (id_incidencia),
    FOREIGN KEY (id_plaga)        REFERENCES tab_catalogo_plaga(id_plaga),
    FOREIGN KEY (id_persona)      REFERENCES tab_personas(id_persona) ON DELETE RESTRICT,
    FOREIGN KEY (id_trabajador)   REFERENCES tab_trabajadores(id_trabajador) ON DELETE RESTRICT,
    FOREIGN KEY (id_monit_period) REFERENCES tab_monitoreo_periodico(id_monit_period),
    FOREIGN KEY (id_lot_prod)     REFERENCES tab_lote_productivo(id_lot_prod)
);
CREATE INDEX IF NOT EXISTS idx_incidencia_lote_prod   ON tab_incidencia_sanitaria(id_lot_prod);
CREATE INDEX IF NOT EXISTS idx_incidencia_monitoreo   ON tab_incidencia_sanitaria(id_monit_period);
CREATE INDEX IF NOT EXISTS idx_incidencia_plaga       ON tab_incidencia_sanitaria(id_plaga);
CREATE INDEX IF NOT EXISTS idx_incidencia_persona     ON tab_incidencia_sanitaria(id_persona);
CREATE INDEX IF NOT EXISTS idx_incidencia_trabajador  ON tab_incidencia_sanitaria(id_trabajador);
CREATE INDEX IF NOT EXISTS idx_incidencia_activas   ON tab_incidencia_sanitaria(id_lot_prod) WHERE estado IN ('activa','reincidente');

CREATE TABLE IF NOT EXISTS tab_tratamiento_aplicado
(
    id_trat_aplic        INT GENERATED ALWAYS AS IDENTITY,
    id_incidencia        INT NOT NULL,
    id_tratamiento       SMALLINT      NOT NULL,
    id_actividad         INT           NULL,     -- V2: viene del catalogo de tratamiento de V1
    id_persona           DECIMAL(10,0) NOT NULL,   -- quien lo registra: agricultor o tecnico
    id_trabajador        INT           NULL,       -- quien aplico el tratamiento; NULL = lo aplico quien lo registra
    id_lot_prod          INT NULL,     -- opcional para asociar plagas comunes a ciertos lotes/productores
    id_aplicacion_insumo INT           NULL,     -- V2: el insumo aplicado (V1: id_insumo)
    fec_aplicacion       DATE          NOT NULL CHECK (fec_aplicacion >= DATE '1950-01-01'),
    dosis                VARCHAR(60)   NOT NULL CHECK (BTRIM(dosis) <> ''),        -- ej. '2 L/ha', '500 g/árbol'
    cantid_plantas       NUMERIC(10,0) NOT NULL CHECK (cantid_plantas >= 0),
    resultado            VARCHAR(20)   NOT NULL CHECK (resultado IN ('Efectivo','Parcial','Sin_efecto')),
    observaciones        TEXT          NULL,
    PRIMARY KEY (id_trat_aplic),
    FOREIGN KEY (id_incidencia)        REFERENCES tab_incidencia_sanitaria(id_incidencia),
    FOREIGN KEY (id_tratamiento)       REFERENCES tab_catalogo_tratamiento(id_tratamiento),
    FOREIGN KEY (id_actividad)         REFERENCES tab_actividades(id_actividad) ON DELETE RESTRICT ON UPDATE RESTRICT,
    FOREIGN KEY (id_aplicacion_insumo) REFERENCES tab_aplicacion_insumo(id_aplicacion) ON DELETE RESTRICT ON UPDATE RESTRICT,
    FOREIGN KEY (id_persona )          REFERENCES tab_personas(id_persona) ON DELETE RESTRICT,
    FOREIGN KEY (id_trabajador)        REFERENCES tab_trabajadores(id_trabajador) ON DELETE RESTRICT,
    FOREIGN KEY (id_lot_prod)          REFERENCES tab_lote_productivo(id_lot_prod)
);
CREATE INDEX IF NOT EXISTS idx_trat_aplic_incidencia  ON tab_tratamiento_aplicado(id_incidencia);
CREATE INDEX IF NOT EXISTS idx_trat_aplic_tratamiento ON tab_tratamiento_aplicado(id_tratamiento);
CREATE INDEX IF NOT EXISTS idx_trat_aplic_persona     ON tab_tratamiento_aplicado(id_persona);
CREATE INDEX IF NOT EXISTS idx_trat_aplic_trabajador  ON tab_tratamiento_aplicado(id_trabajador);
CREATE INDEX IF NOT EXISTS idx_trat_aplic_lote_prod   ON tab_tratamiento_aplicado(id_lot_prod);
CREATE INDEX IF NOT EXISTS idx_trat_aplic_actividad   ON tab_tratamiento_aplicado(id_actividad);
CREATE INDEX IF NOT EXISTS idx_trat_aplic_aplicacion  ON tab_tratamiento_aplicado(id_aplicacion_insumo);

CREATE TABLE IF NOT EXISTS tab_monitoreo_plaga_det
(
    id_mon_det      INT GENERATED ALWAYS AS IDENTITY,
    id_trat_aplic   INT NOT NULL,
    fech_monitoreo  DATE          NOT NULL CHECK (fech_monitoreo >= DATE '1950-01-01'),
    estado          VARCHAR(20)   CHECK (estado IN ('Efectivo','Parcial','Sin_efecto')),

    PRIMARY KEY (id_mon_det),
    FOREIGN KEY (id_trat_aplic) REFERENCES tab_tratamiento_aplicado(id_trat_aplic)
);
CREATE INDEX IF NOT EXISTS idx_monit_plaga_det_trat ON tab_monitoreo_plaga_det(id_trat_aplic);

--*******************************************************************
--CLIMA Y CONDICIONES AMBIENTALES

CREATE TABLE IF NOT EXISTS tab_registro_climatico
 (
    id_registro      INT GENERATED ALWAYS AS IDENTITY,
    id_finca         VARCHAR(30)   NOT NULL,
    fec_registro     TIMESTAMPTZ   NOT NULL DEFAULT now() CHECK (fec_registro >= TIMESTAMPTZ '1950-01-01 00:00:00+00'),
    temp_max_c       NUMERIC(5,2)  NULL CHECK (temp_max_c BETWEEN -10 AND 50),
    temp_min_c       NUMERIC(5,2)  NULL CHECK (temp_min_c BETWEEN -10 AND 50),
    humedad_pct      NUMERIC(5,2)  NULL CHECK (humedad_pct BETWEEN 0 AND 100),
    precipitacion_mm NUMERIC(7,2)  NULL CHECK (precipitacion_mm IS NULL OR precipitacion_mm >= 0), -- V2: lluvia
    observaciones    TEXT          NULL,
    PRIMARY KEY (id_registro),
    UNIQUE (id_finca, fec_registro),
    CHECK (temp_max_c IS NULL OR temp_min_c IS NULL OR temp_max_c >= temp_min_c),
    CHECK (COALESCE(temp_max_c, temp_min_c, humedad_pct, precipitacion_mm) IS NOT NULL),  -- al menos un dato medido
    FOREIGN KEY (id_finca) REFERENCES tab_finca(id_finca)
);

CREATE TABLE IF NOT EXISTS tab_alerta_climatica
(
    id_alerta       INT GENERATED ALWAYS AS IDENTITY,
    id_finca        VARCHAR(30)   NOT NULL,
    id_persona      DECIMAL(10,0) NULL,       -- técnico que emite la alerta (NULL si automática)
    tip_alerta      VARCHAR(30)   NOT NULL CHECK (tip_alerta IN ( 'Sequia','Exceso_lluvia','Helada','Granizo', 'Viento_fuerte','Temperatura_alta','Inundacion')),
    nivel_riesgo    VARCHAR(10)   NOT NULL CHECK (nivel_riesgo IN ('Bajo','Medio','Alto','Critico')),
    fec_inicio      DATE          NOT NULL CHECK (fec_inicio >= DATE '1950-01-01'),
    fec_fin         DATE          NULL,
    descripcion     TEXT          NULL,
    accion_tomada   TEXT          NULL,
    estado          VARCHAR(20)   NOT NULL DEFAULT 'activa' CHECK (estado IN ('activa','resuelta','falsa_alarma')),
    PRIMARY KEY (id_alerta),
    CHECK (fec_fin IS NULL OR fec_fin >= fec_inicio),
    CHECK (estado <> 'resuelta' OR fec_fin IS NOT NULL),       -- una alerta resuelta tiene fecha de fin
    FOREIGN KEY (id_finca)    REFERENCES tab_finca(id_finca),
    FOREIGN KEY (id_persona)  REFERENCES tab_personas(id_persona) ON DELETE RESTRICT ON UPDATE RESTRICT -- V1: SET NULL
);
CREATE INDEX IF NOT EXISTS idx_alerta_clima_finca   ON tab_alerta_climatica(id_finca, fec_inicio DESC);
CREATE INDEX IF NOT EXISTS idx_alerta_clima_persona ON tab_alerta_climatica(id_persona);

--*******************************************************************
-- BENEFICIO: RECOLECCION -> FERMENTACION -> SECADO (todo en kg)

CREATE TABLE IF NOT EXISTS tab_recoleccion
(
    id_recoleccion    INT GENERATED ALWAYS AS IDENTITY,
    id_cosecha        INT NOT NULL, -- Vinculación directa al origen
    id_persona        DECIMAL(10,0) NOT NULL, -- Responsable del acopio en la plataforma (agricultor o tecnico)
    id_trabajador     INT           NULL,     -- quien hizo el acopio; NULL = lo hizo el responsable
    fecha_recoleccion DATE          NOT NULL CHECK (fecha_recoleccion >= DATE '1950-01-01'),
    peso_entrada_kg   NUMERIC(12,2) NOT NULL CHECK (peso_entrada_kg > 0), -- V1: cantidad_entrada + unidad_medida

    PRIMARY KEY(id_recoleccion),
    UNIQUE(id_cosecha), -- 1 Cosecha = 1 Registro de recolección
    FOREIGN KEY(id_cosecha)    REFERENCES tab_cosecha(id_cosecha) ON DELETE RESTRICT,
    FOREIGN KEY(id_persona)    REFERENCES tab_personas(id_persona) ON DELETE RESTRICT,
    FOREIGN KEY(id_trabajador) REFERENCES tab_trabajadores(id_trabajador) ON DELETE RESTRICT
);
CREATE INDEX IF NOT EXISTS idx_recoleccion_persona    ON tab_recoleccion(id_persona);
CREATE INDEX IF NOT EXISTS idx_recoleccion_trabajador ON tab_recoleccion(id_trabajador);

CREATE TABLE IF NOT EXISTS tab_fermentacion
(
    id_fermentacion   INT GENERATED ALWAYS AS IDENTITY,
    id_recoleccion    INT NOT NULL, -- Cadena estricta
    id_persona        DECIMAL(10,0) NOT NULL, -- Responsable en la plataforma (agricultor o tecnico)
    id_trabajador     INT           NULL,     -- quien hizo la fermentacion (volteos); NULL = la hizo el responsable
    fecha_inicio      DATE          NOT NULL CHECK (fecha_inicio >= DATE '1950-01-01'),
    fecha_fin         DATE          NULL,
    peso_salida_kg    NUMERIC(12,2) NULL CHECK (peso_salida_kg IS NULL OR peso_salida_kg > 0),
    metodo            VARCHAR(50)   NOT NULL CHECK (BTRIM(metodo) <> ''), -- Ej: 'Cajas de madera', 'Montones'
    dias_duracion     DECIMAL(3,0)  NOT NULL CHECK (dias_duracion BETWEEN 1 AND 10),
    volteos_realizados DECIMAL(3,0) NOT NULL DEFAULT 0 CHECK (volteos_realizados >= 0),
    temp_maxima_c     NUMERIC(5,2)  NULL CHECK (temp_maxima_c IS NULL OR temp_maxima_c BETWEEN 0 AND 70), -- V2

    PRIMARY KEY(id_fermentacion),
    UNIQUE(id_recoleccion), -- 1 Recolección = 1 Fermentación
    FOREIGN KEY(id_recoleccion) REFERENCES tab_recoleccion(id_recoleccion) ON DELETE RESTRICT ON UPDATE RESTRICT, -- V1: CASCADE
    FOREIGN KEY(id_persona) REFERENCES tab_personas(id_persona) ON DELETE RESTRICT,
    FOREIGN KEY(id_trabajador) REFERENCES tab_trabajadores(id_trabajador) ON DELETE RESTRICT,
    CHECK (fecha_fin IS NULL OR fecha_fin >= fecha_inicio)
);
CREATE INDEX IF NOT EXISTS idx_fermentacion_persona    ON tab_fermentacion(id_persona);
CREATE INDEX IF NOT EXISTS idx_fermentacion_trabajador ON tab_fermentacion(id_trabajador);

CREATE TABLE IF NOT EXISTS tab_secado
(
    id_secado         INT GENERATED ALWAYS AS IDENTITY,
    id_fermentacion   INT NOT NULL, -- Cadena estricta
    id_persona        DECIMAL(10,0) NOT NULL, -- Responsable en la plataforma (agricultor o tecnico)
    id_trabajador     INT           NULL,     -- quien hizo el secado; NULL = lo hizo el responsable
    fecha_inicio      DATE          NOT NULL CHECK (fecha_inicio >= DATE '1950-01-01'),
    fecha_fin         DATE          NULL,
    CHECK (fecha_fin IS NULL OR fecha_fin >= fecha_inicio),
    metodo            VARCHAR(50)   NOT NULL CHECK (BTRIM(metodo) <> ''), -- Ej: 'Solar (marquesina)', 'Mecánico'
    peso_salida_kg    NUMERIC(12,2) NULL CHECK (peso_salida_kg > 0),
    humedad_final_pct DECIMAL(5,2)  NULL CHECK (humedad_final_pct BETWEEN 5.0 AND 12.0), -- V2: se conoce al terminar
    PRIMARY KEY(id_secado),
    UNIQUE(id_fermentacion), -- 1 Fermentación = 1 Secado
    CHECK (fecha_fin IS NULL OR humedad_final_pct IS NOT NULL), -- al cerrar el secado la humedad es obligatoria
    FOREIGN KEY(id_fermentacion) REFERENCES tab_fermentacion(id_fermentacion) ON DELETE RESTRICT ON UPDATE RESTRICT, -- V1: CASCADE
    FOREIGN KEY(id_persona) REFERENCES tab_personas(id_persona) ON DELETE RESTRICT,
    FOREIGN KEY(id_trabajador) REFERENCES tab_trabajadores(id_trabajador) ON DELETE RESTRICT
);
CREATE INDEX IF NOT EXISTS idx_secado_persona    ON tab_secado(id_persona);
CREATE INDEX IF NOT EXISTS idx_secado_trabajador ON tab_secado(id_trabajador);

--*******************************************************************
-- BODEGA Y VENTA EN GRANO


---- REVISAAR SI EFECTIVAMENTE SE NECESITA LA TABLA, PORQUE CREO QUE HACE LOO MISMO QUE LA DEA 
CREATE TABLE IF NOT EXISTS tab_bodega
(
    id_bodega   INT GENERATED ALWAYS AS IDENTITY,   -- V2: autonumerica (V1: DECIMAL(4,0) a mano)
    id_finca    VARCHAR(30)   NOT NULL,
    nom_bodega  VARCHAR(100)  NOT NULL CHECK (BTRIM(nom_bodega) <> ''),
    cap_max_kg  NUMERIC(12,2) NOT NULL CHECK (cap_max_kg > 0),
    condiciones VARCHAR(100),
    PRIMARY KEY(id_bodega),
    FOREIGN KEY(id_finca) REFERENCES tab_finca(id_finca)
);
CREATE INDEX IF NOT EXISTS idx_bodega_finca ON tab_bodega(id_finca);

-- Lote de grano guardado en bodega. Es lo que se vende.
CREATE TABLE IF NOT EXISTS tab_inventario_bodega
(
    id_inventario  INT GENERATED ALWAYS AS IDENTITY,
    id_bodega      INT           NOT NULL,
    id_cosecha     INT NOT NULL,
    estado_grano   VARCHAR(10)   NOT NULL DEFAULT 'Seco' CHECK (estado_grano IN ('Baba','Seco')), -- V2: el precio cambia mucho entre baba y seco
    fec_ingreso    DATE          NOT NULL CHECK (fec_ingreso >= DATE '1950-01-01'),
    fec_salida     DATE          NULL,
    cant_kg_ingres NUMERIC(12,2) NOT NULL CHECK (cant_kg_ingres > 0),
    cant_kg_actual NUMERIC(12,2) NOT NULL CHECK (cant_kg_actual >= 0 AND cant_kg_actual <= cant_kg_ingres), -- lo descuenta tab_venta_detalle
    CHECK (fec_salida IS NULL OR fec_salida >= fec_ingreso),
    CHECK (fec_salida IS NULL OR cant_kg_actual = 0),   -- fecha de salida solo cuando el lote quedo vacio
    PRIMARY KEY(id_inventario),
    FOREIGN KEY(id_bodega)  REFERENCES tab_bodega(id_bodega),
    FOREIGN KEY(id_cosecha) REFERENCES tab_cosecha(id_cosecha)
);
CREATE INDEX IF NOT EXISTS idx_inventario_bodega     ON tab_inventario_bodega(id_bodega);
CREATE INDEX IF NOT EXISTS idx_inventario_cosecha    ON tab_inventario_bodega(id_cosecha);
CREATE INDEX IF NOT EXISTS idx_inventario_disponible ON tab_inventario_bodega(id_bodega, estado_grano) WHERE cant_kg_actual > 0;

CREATE TABLE IF NOT EXISTS tab_ventas
(
    id_venta      INT GENERATED ALWAYS AS IDENTITY,
    id_persona    DECIMAL(10,0)  NOT NULL, -- Responsable
    cant_kg       NUMERIC(12,2)  NOT NULL CHECK (cant_kg > 0),
    precio_kg     NUMERIC(12,2)  NOT NULL CHECK (precio_kg > 0),
    valor_total   NUMERIC(16,2)  NOT NULL CHECK (valor_total > 0),
    fec_venta     TIMESTAMPTZ    NOT NULL DEFAULT CURRENT_TIMESTAMP CHECK (fec_venta >= TIMESTAMPTZ '1950-01-01 00:00:00+00'),
    PRIMARY KEY(id_venta),
    CHECK (ABS(valor_total - cant_kg * precio_kg) <= cant_kg * 0.005 + 0.01), -- el total y el precio por kg no se contradicen
    FOREIGN KEY(id_persona) REFERENCES tab_productor(id_persona)
);
CREATE INDEX IF NOT EXISTS idx_ventas_persona_fecha ON tab_ventas(id_persona, fec_venta DESC);

-- V2: de que lote de bodega sale el grano vendido (venta -> bodega -> cosecha -> finca)
CREATE TABLE IF NOT EXISTS tab_venta_detalle
(
    id_venta      INT           NOT NULL,
    id_inventario INT           NOT NULL,
    cant_kg       NUMERIC(12,2) NOT NULL CHECK (cant_kg > 0),
    PRIMARY KEY(id_venta, id_inventario),
    FOREIGN KEY(id_venta)      REFERENCES tab_ventas(id_venta)                 ON DELETE RESTRICT ON UPDATE RESTRICT,
    FOREIGN KEY(id_inventario) REFERENCES tab_inventario_bodega(id_inventario) ON DELETE RESTRICT ON UPDATE RESTRICT
);
CREATE INDEX IF NOT EXISTS idx_venta_detalle_inventario ON tab_venta_detalle(id_inventario);

-- Jornales/pagos del "Mano de Obra" del dashboard: el productor registra una jornada
-- para uno de sus trabajadores y luego marca el pago.
CREATE TABLE IF NOT EXISTS tab_jornales
(
    id_jornal       INT GENERATED ALWAYS AS IDENTITY,
    id_persona      DECIMAL(10,0)  NOT NULL, -- productor que registra la jornada
    id_trabajador   INT            NOT NULL, -- V2: si la plataforma envia solo el nombre, trg_jornales_trabajador lo busca o lo agrega al listado
    trabajador      VARCHAR(120)   NULL CHECK (BTRIM(trabajador) <> ''),  -- DEPRECADA: copia del nombre mientras la plataforma la lea
    labor           VARCHAR(60)    NOT NULL CHECK (BTRIM(labor) <> ''),
    id_lote         DECIMAL(10,0)  NULL,      -- V2: el lote como llave
    lote_desc       VARCHAR(150)   NULL,      -- DEPRECADA: texto "Finca - Lote"
    fecha           DATE           NOT NULL CHECK (fecha >= DATE '1950-01-01'),
    monto           NUMERIC(12,2)  NOT NULL CHECK (monto >= 0),  -- 0 admitido: mano vuelta (trabajo de intercambio)
    estado          VARCHAR(10)    NOT NULL DEFAULT 'PENDIENTE' CHECK (estado IN ('PENDIENTE','PAGADO')),
    metodo_pago     VARCHAR(30)    NULL,
    referencia_pago VARCHAR(60)    NULL,
    fecha_pago      DATE           NULL,
    observaciones   TEXT           NULL,
    CHECK ((estado = 'PENDIENTE' AND fecha_pago IS NULL AND metodo_pago IS NULL AND referencia_pago IS NULL)  -- pendiente: sin datos de pago
        OR (estado = 'PAGADO' AND fecha_pago IS NOT NULL)),                                                -- pagado: con fecha de pago
    PRIMARY KEY(id_jornal),
    FOREIGN KEY(id_persona) REFERENCES tab_personas(id_persona) ON DELETE RESTRICT,
    FOREIGN KEY(id_trabajador, id_persona) REFERENCES tab_trabajadores(id_trabajador, id_persona) ON DELETE RESTRICT ON UPDATE RESTRICT, -- el trabajador es de quien paga
    FOREIGN KEY(id_lote)    REFERENCES tab_lotes(id_lote) ON DELETE RESTRICT ON UPDATE RESTRICT
);
CREATE INDEX IF NOT EXISTS idx_jornales_persona_fecha ON tab_jornales(id_persona, fecha DESC);
CREATE INDEX IF NOT EXISTS idx_jornales_trabajador    ON tab_jornales(id_trabajador, id_persona, fecha DESC);
CREATE INDEX IF NOT EXISTS idx_jornales_lote          ON tab_jornales(id_lote);

-- Costo de mano de obra: un jornal por fila con su trabajador, lote y finca.
-- Ej. cuanto lleva pagado Ana este año, por trabajador:
--   SELECT trabajador, SUM(monto) FROM vw_mano_obra
--    WHERE id_persona = 1001 AND estado = 'PAGADO' AND fecha >= DATE '2026-01-01' GROUP BY trabajador;
CREATE OR REPLACE VIEW vw_mano_obra AS
SELECT j.id_jornal,
       j.id_persona,
       j.fecha,
       j.labor,
       j.monto,
       j.estado,
       j.fecha_pago,
       t.id_trabajador,
       t.nom_trabajador AS trabajador,
       j.id_lote,
       l.nom_lote,
       l.id_finca,
       f.nom_finca
  FROM tab_jornales j
  JOIN tab_trabajadores t ON t.id_trabajador = j.id_trabajador
  LEFT JOIN tab_lotes l ON l.id_lote = j.id_lote
  LEFT JOIN tab_finca f ON f.id_finca = l.id_finca;

-- Que hizo cada trabajador: una fila por labor registrada con id_trabajador, venga de la tabla que venga.
-- Ej. labores de un trabajador:
--   SELECT fecha, labor, nom_lote FROM vw_labores_trabajador WHERE id_trabajador = 7 ORDER BY fecha DESC;
CREATE OR REPLACE VIEW vw_labores_trabajador AS
WITH lote_de_lot_prod AS (   -- lote al que pertenece cada lote productivo
    SELECT lp.id_lot_prod, pl.id_lote
      FROM tab_lote_productivo lp
      JOIN tab_analisis_suelo s     ON s.id_analisis     = lp.id_analisis
      JOIN tab_preparacion_lotes pl ON pl.id_preparacion = s.id_preparacion
),
labores AS (
    SELECT a.id_trabajador, 'tab_actividades'::VARCHAR(30) AS tabla, a.id_actividad AS id_registro, a.fech_inicio AS fecha,
           a.nom_actividad::VARCHAR(120) AS labor, a.id_lote
      FROM tab_actividades a WHERE a.id_trabajador IS NOT NULL
    UNION ALL
    SELECT p.id_trabajador, 'tab_preparacion_lotes', p.id_preparacion, p.fecha_evaluacion, 'Preparación del lote', p.id_lote
      FROM tab_preparacion_lotes p WHERE p.id_trabajador IS NOT NULL
    UNION ALL
    SELECT c.id_trabajador, 'tab_cosecha', c.id_cosecha, c.fech_cosecha, 'Cosecha', ll.id_lote
      FROM tab_cosecha c JOIN lote_de_lot_prod ll ON ll.id_lot_prod = c.id_lot_prod WHERE c.id_trabajador IS NOT NULL
    UNION ALL
    SELECT m.id_trabajador, 'tab_monitoreo_periodico', m.id_monit_period, m.fech_inspec, 'Monitoreo del cultivo', ll.id_lote
      FROM tab_monitoreo_periodico m JOIN lote_de_lot_prod ll ON ll.id_lot_prod = m.id_lot_prod WHERE m.id_trabajador IS NOT NULL
    UNION ALL
    SELECT i.id_trabajador, 'tab_incidencia_sanitaria', i.id_incidencia, i.fec_deteccion, 'Detección de plaga o enfermedad', ll.id_lote
      FROM tab_incidencia_sanitaria i JOIN lote_de_lot_prod ll ON ll.id_lot_prod = i.id_lot_prod WHERE i.id_trabajador IS NOT NULL
    UNION ALL
    SELECT t.id_trabajador, 'tab_tratamiento_aplicado', t.id_trat_aplic, t.fec_aplicacion, 'Tratamiento fitosanitario', ll.id_lote
      FROM tab_tratamiento_aplicado t
      JOIN tab_incidencia_sanitaria i ON i.id_incidencia = t.id_incidencia
      JOIN lote_de_lot_prod ll        ON ll.id_lot_prod  = COALESCE(t.id_lot_prod, i.id_lot_prod)
     WHERE t.id_trabajador IS NOT NULL
    UNION ALL
    SELECT r.id_trabajador, 'tab_recoleccion', r.id_recoleccion, r.fecha_recoleccion, 'Recolección y acopio', ll.id_lote
      FROM tab_recoleccion r
      JOIN tab_cosecha c       ON c.id_cosecha   = r.id_cosecha
      JOIN lote_de_lot_prod ll ON ll.id_lot_prod = c.id_lot_prod
     WHERE r.id_trabajador IS NOT NULL
    UNION ALL
    SELECT fe.id_trabajador, 'tab_fermentacion', fe.id_fermentacion, fe.fecha_inicio, 'Fermentación', ll.id_lote
      FROM tab_fermentacion fe
      JOIN tab_recoleccion r   ON r.id_recoleccion = fe.id_recoleccion
      JOIN tab_cosecha c       ON c.id_cosecha     = r.id_cosecha
      JOIN lote_de_lot_prod ll ON ll.id_lot_prod   = c.id_lot_prod
     WHERE fe.id_trabajador IS NOT NULL
    UNION ALL
    SELECT se.id_trabajador, 'tab_secado', se.id_secado, se.fecha_inicio, 'Secado', ll.id_lote
      FROM tab_secado se
      JOIN tab_fermentacion fe ON fe.id_fermentacion = se.id_fermentacion
      JOIN tab_recoleccion r   ON r.id_recoleccion   = fe.id_recoleccion
      JOIN tab_cosecha c       ON c.id_cosecha       = r.id_cosecha
      JOIN lote_de_lot_prod ll ON ll.id_lot_prod     = c.id_lot_prod
     WHERE se.id_trabajador IS NOT NULL
)
SELECT la.id_trabajador,
       tr.nom_trabajador AS trabajador,
       tr.id_persona,          -- agricultor dueño del listado
       la.fecha,
       la.labor,
       la.tabla,
       la.id_registro,
       la.id_lote,
       l.nom_lote,
       l.id_finca
  FROM labores la
  JOIN tab_trabajadores tr ON tr.id_trabajador = la.id_trabajador
  LEFT JOIN tab_lotes l    ON l.id_lote = la.id_lote;

-- Bodega de insumos (fertilizantes, fungicidas, herramientas) del módulo Inventario del dashboard
CREATE TABLE IF NOT EXISTS tab_inventario_insumos
(
    id_inventario  INT GENERATED ALWAYS AS IDENTITY,
    id_persona     DECIMAL(10,0) NOT NULL,
    nombre         VARCHAR(100)  NOT NULL CHECK (BTRIM(nombre) <> ''),
    categoria      VARCHAR(60)   NOT NULL CHECK (BTRIM(categoria) <> ''),
    cantidad       NUMERIC(10,2) NOT NULL CHECK (cantidad >= 0),
    unidad         VARCHAR(30)   NOT NULL CHECK (BTRIM(unidad) <> ''),
    estado         VARCHAR(20)   NOT NULL DEFAULT 'SUFICIENTE' CHECK (estado IN ('SUFICIENTE','CRÍTICO','MANTENIMIENTO')),
    fecha_registro DATE          NOT NULL DEFAULT CURRENT_DATE CHECK (fecha_registro >= DATE '1950-01-01'),
    
    PRIMARY KEY(id_inventario),
   
    FOREIGN KEY(id_persona) REFERENCES tab_personas(id_persona) ON DELETE RESTRICT
);
CREATE INDEX IF NOT EXISTS idx_inv_insumos_persona ON tab_inventario_insumos(id_persona, fecha_registro DESC);

-- V2: lo registra el tecnico o el agricultor; el laboratorio/comprador/ente que analizo va en ente_analiza
CREATE TABLE IF NOT EXISTS tab_analisis_calidad
(
    id_analisis         INT GENERATED ALWAYS AS IDENTITY,
    id_cosecha          INT NOT NULL,
    id_persona_registra DECIMAL(10,0) NULL,      -- V1: id_persona del regulador
    ente_analiza        VARCHAR(150)  NOT NULL CHECK (BTRIM(ente_analiza) <> ''),
    fec_analisis        DATE          NOT NULL CHECK (fec_analisis >= DATE '1950-01-01'),
    muestra_kg          NUMERIC(8,2)  NOT NULL CHECK (muestra_kg > 0),
    granos_sanos        DECIMAL(5,2)  CHECK (granos_sanos      BETWEEN 0 AND 100),
    granos_ferment      DECIMAL(5,2)  CHECK (granos_ferment    BETWEEN 0 AND 100),
    granos_violetas     DECIMAL(5,2)  CHECK (granos_violetas   BETWEEN 0 AND 100),
    granos_pizarrosos   DECIMAL(5,2)  CHECK (granos_pizarrosos BETWEEN 0 AND 100),
    granos_mohosos      DECIMAL(5,2)  CHECK (granos_mohosos    BETWEEN 0 AND 100),
    granos_germinad     DECIMAL(5,2)  CHECK (granos_germinad   BETWEEN 0 AND 100),
    humedad_porcent     DECIMAL(5,2)  CHECK (humedad_porcent   BETWEEN 0 AND 100),
    indice_ferment      DECIMAL(5,2)  CHECK (indice_ferment >= 0),
    id_calidad          SMALLINT      NULL,      -- V1: clasificacion ('Fino','Corriente','Pasilla')
    observaciones       TEXT,
    -- prueba de corte: fermentados, violetas, pizarrosos, mohosos y germinados son clases distintas
    CHECK (COALESCE(granos_ferment, 0) + COALESCE(granos_violetas, 0) + COALESCE(granos_pizarrosos, 0)
         + COALESCE(granos_mohosos, 0) + COALESCE(granos_germinad, 0) <= 100),
    PRIMARY KEY(id_analisis),
    FOREIGN KEY(id_cosecha)          REFERENCES tab_cosecha(id_cosecha),
    FOREIGN KEY(id_persona_registra) REFERENCES tab_personas(id_persona) ON DELETE RESTRICT ON UPDATE RESTRICT,
    FOREIGN KEY(id_calidad)          REFERENCES tab_catalogo_calidad_cacao(id_calidad) ON DELETE RESTRICT ON UPDATE RESTRICT
);
CREATE INDEX IF NOT EXISTS idx_analisis_cal_cosecha  ON tab_analisis_calidad(id_cosecha);
CREATE INDEX IF NOT EXISTS idx_analisis_cal_registra ON tab_analisis_calidad(id_persona_registra);
CREATE INDEX IF NOT EXISTS idx_analisis_cal_calidad  ON tab_analisis_calidad(id_calidad);


INSERT INTO tab_parametros_seguridad DEFAULT VALUES;

INSERT INTO tab_roles (id_rol, nom_rol, codigo_rol, descripcion) VALUES
    (2, 'Agricultor', 'AGRICULTOR', 'Cacaocultor titular: gestiona sus fincas desde la siembra hasta la venta del grano.'),
    (5, 'Técnico',    'TECNICO',    'Asistente técnico: consulta y registra información agronómica de las fincas que el agricultor le vincula.');

INSERT INTO tab_permisos (id_permiso, descrip_perm, codigo_permiso) VALUES
    (101, 'Consultar fincas y lotes autorizados',                                     'FINCA_VER'),
    (102, 'Registrar y editar fincas, lotes y variedades de la finca',                'FINCA_GESTIONAR'),
    (103, 'Vincular y desvincular personas (incluido el técnico) a una finca',        'FINCA_VINCULAR'),
    (104, 'Consultar actividades y calendario agrícola',                              'CALENDARIO_VER'),
    (105, 'Programar y actualizar actividades del calendario agrícola',               'CALENDARIO_GESTIONAR'),
    (106, 'Registrar preparación de lotes, siembra, lotes productivos y metas',       'CULTIVO_GESTIONAR'),
    (107, 'Registrar análisis de suelo',                                              'SUELO_REGISTRAR'),
    (108, 'Dictaminar la aptitud de un análisis de suelo',                            'SUELO_DICTAMINAR'),
    (109, 'Registrar monitoreos, incidencias y tratamientos fitosanitarios',          'SANIDAD_REGISTRAR'),
    (110, 'Registrar aplicaciones de insumos',                                        'INSUMO_APLICAR'),
    (111, 'Registrar datos y alertas climáticas',                                     'CLIMA_REGISTRAR'),
    (112, 'Registrar cosecha, recolección, fermentación, secado y bodega',            'BENEFICIO_GESTIONAR'),
    (113, 'Registrar análisis de calidad del grano',                                  'CALIDAD_REGISTRAR'),
    (114, 'Registrar y consultar ventas de grano',                                    'VENTA_GESTIONAR'),
    (115, 'Registrar jornales y pagos de mano de obra',                               'MANO_OBRA_GESTIONAR'),
    (116, 'Gestionar inventario de insumos y herramientas',                           'INVENTARIO_GESTIONAR'),
    (118, 'Ampliar catálogos técnicos: plagas, tratamientos, insumos, herramientas',  'CATALOGO_GESTIONAR'),
    (119, 'Gestionar perfil y sesiones propios',                                      'CUENTA_PROPIA');

-- Agricultor: todo menos dictaminar suelo y ampliar catalogos
INSERT INTO tab_rol_permisos (id_rol, id_permiso) VALUES
    (2, 101), (2, 102), (2, 103), (2, 104), (2, 105), (2, 106), (2, 107), (2, 109), (2, 110),
    (2, 111), (2, 112), (2, 113), (2, 114), (2, 115), (2, 116), (2, 119);
-- Tecnico: solo lo agronomico; no ve ventas, jornales ni inventario del agricultor
INSERT INTO tab_rol_permisos (id_rol, id_permiso) VALUES
    (5, 101), (5, 104), (5, 105), (5, 107), (5, 108), (5, 109), (5, 110), (5, 111), (5, 113), (5, 118), (5, 119);

INSERT INTO tab_finalidades_tratamiento (id_finalidad, codigo, descripcion, ind_obligatoria) VALUES
    (1, 'CUENTA_PLATAFORMA',  'Crear y administrar la cuenta de acceso, autenticar al titular y proteger la seguridad de la plataforma.', TRUE),
    (2, 'GESTION_PRODUCTIVA', 'Registrar y procesar la información de fincas, lotes, cultivo, beneficio y venta de cacao del titular para prestarle el servicio.', TRUE),
    (3, 'ASISTENCIA_TECNICA', 'Compartir la información agronómica de las fincas con los técnicos que el titular vincule.', FALSE),
    (4, 'COMUNICACIONES',     'Enviar alertas climáticas, recordatorios del calendario y comunicaciones por correo o SMS.', FALSE);

-- Equivalencias colombianas: 1 arroba = 12,5 kg; 1 quintal = 50 kg
INSERT INTO tab_unidad_medida (sigla, nom_unidad, magnitud, factor_base) VALUES
    ('kg',     'Kilogramo',        'Masa',    1),
    ('g',      'Gramo',            'Masa',    0.001),
    ('lb',     'Libra',            'Masa',    0.45359237),
    ('Arroba', 'Arroba (12,5 kg)', 'Masa',    12.5),
    ('qq',     'Quintal (50 kg)',  'Masa',    50),
    ('Bulto',  'Bulto (50 kg)',    'Masa',    50),
    ('L',      'Litro',            'Volumen', 1),
    ('mL',     'Mililitro',        'Volumen', 0.001),
    ('gal',    'Galón',            'Volumen', 3.78541178),
    ('Und',    'Unidad',           'Unidad',  NULL);

INSERT INTO tab_catalogo_calidad_cacao (nom_calidad, descripcion) VALUES
    ('Fino',      'Grano fino de sabor y aroma'),
    ('Corriente', 'Grano corriente'),
    ('Pasilla',   'Grano de rechazo: partido, vano, plano o con defectos');
