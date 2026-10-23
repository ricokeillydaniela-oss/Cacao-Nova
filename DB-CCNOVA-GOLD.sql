
SET client_encoding = 'UTF8';

DROP TABLE IF EXISTS fact_calidad; --no quiero calidad
DROP TABLE IF EXISTS fact_suelo;
DROP TABLE IF EXISTS fact_clima;
DROP TABLE IF EXISTS fact_tratamiento;
DROP TABLE IF EXISTS fact_sanidad;
DROP TABLE IF EXISTS fact_meta;
DROP TABLE IF EXISTS fact_jornal;
DROP TABLE IF EXISTS fact_insumo;
DROP TABLE IF EXISTS fact_venta;
DROP TABLE IF EXISTS fact_cosecha;
DROP TABLE IF EXISTS dim_calidad;
DROP TABLE IF EXISTS dim_tratamiento;
DROP TABLE IF EXISTS dim_plaga;
DROP TABLE IF EXISTS dim_insumo;
DROP TABLE IF EXISTS dim_trabajador;
DROP TABLE IF EXISTS dim_productor;
DROP TABLE IF EXISTS dim_variedad;
DROP TABLE IF EXISTS dim_lote;
DROP TABLE IF EXISTS dim_finca;
DROP TABLE IF EXISTS dim_tiempo;

--*******************************************************************************************
-- DIMENSIONES
--*******************************************************************************************

-- Un dia por fila. Se llena al final de este script.
CREATE TABLE IF NOT EXISTS dim_tiempo
(
    id_fecha       INT          NOT NULL,                  -- AAAAMMDD, ej. 20261023
    fecha          DATE         NOT NULL,
    anio           SMALLINT     NOT NULL,
    semestre       SMALLINT     NOT NULL CHECK (semestre BETWEEN 1 AND 2),
    trimestre      SMALLINT     NOT NULL CHECK (trimestre BETWEEN 1 AND 4),
    mes            SMALLINT     NOT NULL CHECK (mes BETWEEN 1 AND 12),
    nom_mes        VARCHAR(10)  NOT NULL,
    anio_mes       VARCHAR(7)   NOT NULL,                  -- '2026-10': etiqueta que ordena bien en los graficos
    semana_anio    SMALLINT     NOT NULL CHECK (semana_anio BETWEEN 1 AND 53),
    dia_mes        SMALLINT     NOT NULL CHECK (dia_mes BETWEEN 1 AND 31),
    dia_semana     SMALLINT     NOT NULL CHECK (dia_semana BETWEEN 1 AND 7),  -- 1 = lunes
    nom_dia        VARCHAR(10)  NOT NULL,
    ind_fin_semana BOOLEAN      NOT NULL,
    PRIMARY KEY(id_fecha),
    UNIQUE(fecha)
);

-- Finca con su municipio y departamento (V2: tab_finca + tab_ciudades + tab_dptos)
CREATE TABLE IF NOT EXISTS dim_finca
(
    id_finca      VARCHAR(30)   NOT NULL,
    nom_finca     VARCHAR(120)  NOT NULL,
    hect_cacao    DECIMAL(10,2) NOT NULL CHECK (hect_cacao >= 0),
    PRIMARY KEY(id_finca)
);


CREATE TABLE IF NOT EXISTS dim_lote
(
    id_lote      DECIMAL(10,0) NOT NULL,
    id_finca     VARCHAR(30)   NOT NULL,
    nom_lote     VARCHAR(100)  NOT NULL,
    area_hecta   DECIMAL(10,2) NOT NULL CHECK (area_hecta >= 0),  -- base del rendimiento kg/ha
    altitud_msnm DECIMAL(5,0)  NULL CHECK (altitud_msnm BETWEEN 0 AND 5000),
    PRIMARY KEY(id_lote),
    FOREIGN KEY(id_finca) REFERENCES dim_finca(id_finca)
);

CREATE TABLE IF NOT EXISTS dim_variedad
(
    id_variedad   DECIMAL(4,0)  NOT NULL,
    nombre_vari   VARCHAR(80)   NOT NULL,
    tipo_cacao    VARCHAR(20)   NOT NULL CHECK (tipo_cacao IN ('Criollo','Forastero','Trinitario','CCN-51','Hibrido','No registrado')),
    rend_promedio DECIMAL(10,2) NULL CHECK (rend_promedio >= 0),   -- referencia para comparar con el rendimiento real
    PRIMARY KEY(id_variedad)
);

CREATE TABLE IF NOT EXISTS dim_productor
(
    id_productor   DECIMAL(10,0) NOT NULL,                 -- id_persona de V2
    nom_productor  VARCHAR(201)  NOT NULL,                 -- nombre y apellido
    tip_productor  VARCHAR(15)   NOT NULL CHECK (tip_productor IN ('Pequeño','Mediano','Grande','No registrado')),
    ind_transforma BOOLEAN       NULL,                     -- fermenta y seca en su finca; NULL = sin ficha de productor
    PRIMARY KEY(id_productor)
);


CREATE TABLE IF NOT EXISTS dim_trabajador
(
    id_trabajador  INT          NOT NULL,
    nom_trabajador VARCHAR(120) NOT NULL,
    PRIMARY KEY(id_trabajador)
);

CREATE TABLE IF NOT EXISTS dim_insumo
(
    id_insumo   INT          NOT NULL,
    nom_insumo  VARCHAR(100) NOT NULL,
    tip_insumo  VARCHAR(20)  NOT NULL CHECK (tip_insumo IN ('Fertilizante','Fungicida','Insecticida','Herbicida','Enmienda','Bioinsumo','Semilla','Otro','No registrado')),
    unidad_base VARCHAR(3)   NULL CHECK (unidad_base IN ('kg','L','Und')),  -- unidad de fact_insumo.cantidad_base
    PRIMARY KEY(id_insumo)
);

CREATE TABLE IF NOT EXISTS dim_plaga
(
    id_plaga       SMALLINT     NOT NULL,
    nom_plaga      VARCHAR(100) NOT NULL,
    tip_agente     VARCHAR(20)  NOT NULL CHECK (tip_agente IN ('Hongo','Bacteria','Insecto','Acaro','Virus','Otro')),
    parte_afectada VARCHAR(50)  NOT NULL,
    PRIMARY KEY(id_plaga)
);

CREATE TABLE IF NOT EXISTS dim_tratamiento
(
    id_tratamiento  SMALLINT     NOT NULL,
    nom_tratamiento VARCHAR(100) NOT NULL,
    tip_tratamiento VARCHAR(20)  NOT NULL CHECK (tip_tratamiento IN ('Quimico','Biologico','Cultural','Mecanico')),
    PRIMARY KEY(id_tratamiento)
);


CREATE TABLE IF NOT EXISTS fact_cosecha
(
    id_cosecha            INT           NOT NULL,
    id_finca              VARCHAR(30)   NOT NULL,
    id_lote               DECIMAL(10,0) NOT NULL,
    peso_cosecha_kg       NUMERIC(12,2) NOT NULL CHECK (peso_cosecha_kg > 0),
    peso_recolectado_kg   NUMERIC(12,2) NULL CHECK (peso_recolectado_kg > 0),
    peso_fermentado_kg    NUMERIC(12,2) NULL CHECK (peso_fermentado_kg > 0),
    peso_seco_kg          NUMERIC(12,2) NULL CHECK (peso_seco_kg > 0),        -- peso_seco_kg / peso_recolectado_kg = factor de conversion
    dias_fermentacion     DECIMAL(3,0)  NULL CHECK (dias_fermentacion >= 0),
    volteos               DECIMAL(3,0)  NULL CHECK (volteos >= 0),
    temp_max_ferm_c       NUMERIC(5,2)  NULL CHECK (temp_max_ferm_c BETWEEN 0 AND 70),
    dias_secado           SMALLINT      NULL CHECK (dias_secado >= 0),
    humedad_final_pct     DECIMAL(5,2)  NULL CHECK (humedad_final_pct BETWEEN 0 AND 100),
    metodo_fermentacion   VARCHAR(50)   NULL,
    metodo_secado         VARCHAR(50)   NULL,
    PRIMARY KEY(id_cosecha),
    FOREIGN KEY(id_fecha)      REFERENCES dim_tiempo(id_fecha),
    FOREIGN KEY(id_finca)      REFERENCES dim_finca(id_finca),
    FOREIGN KEY(id_lote)       REFERENCES dim_lote(id_lote),
    FOREIGN KEY(id_variedad)   REFERENCES dim_variedad(id_variedad),
    FOREIGN KEY(id_productor)  REFERENCES dim_productor(id_productor),
    FOREIGN KEY(id_trabajador) REFERENCES dim_trabajador(id_trabajador),
    FOREIGN KEY(id_calidad)    REFERENCES dim_calidad(id_calidad)
);
CREATE INDEX IF NOT EXISTS idx_fact_cosecha_fecha     ON fact_cosecha(id_fecha);
CREATE INDEX IF NOT EXISTS idx_fact_cosecha_productor ON fact_cosecha(id_productor, id_fecha);

-- Una fila por venta y lote de bodega (V2: tab_venta_detalle). Una venta sin detalle va en una
-- sola fila con id_inventario 0 y finca, lote y variedad 0.
CREATE TABLE IF NOT EXISTS fact_venta
(
    id_venta      INT           NOT NULL,
    id_inventario INT           NOT NULL,
    id_fecha      INT           NOT NULL,                  -- fecha de la venta (hora de Colombia)
    id_finca      VARCHAR(30)   NOT NULL,
    id_lote       DECIMAL(10,0) NOT NULL,
    id_variedad   DECIMAL(4,0)  NOT NULL,
    id_productor  DECIMAL(10,0) NOT NULL,                  -- quien vende
    estado_grano  VARCHAR(15)   NOT NULL CHECK (estado_grano IN ('Baba','Seco','No registrado')),
    cant_kg       NUMERIC(12,2) NOT NULL CHECK (cant_kg > 0),
    precio_kg     NUMERIC(12,2) NOT NULL CHECK (precio_kg > 0),
    valor         NUMERIC(16,2) NOT NULL CHECK (valor > 0),  -- cant_kg * precio_kg; precio promedio = SUM(valor) / SUM(cant_kg)
    PRIMARY KEY(id_venta, id_inventario),
    FOREIGN KEY(id_fecha)     REFERENCES dim_tiempo(id_fecha),
    FOREIGN KEY(id_finca)     REFERENCES dim_finca(id_finca),
    FOREIGN KEY(id_lote)      REFERENCES dim_lote(id_lote),
    FOREIGN KEY(id_variedad)  REFERENCES dim_variedad(id_variedad),
    FOREIGN KEY(id_productor) REFERENCES dim_productor(id_productor)
);
CREATE INDEX IF NOT EXISTS idx_fact_venta_fecha     ON fact_venta(id_fecha);
CREATE INDEX IF NOT EXISTS idx_fact_venta_productor ON fact_venta(id_productor, id_fecha);

-- Una fila por aplicacion de insumo (V2: tab_aplicacion_insumo). Costo de insumos.
CREATE TABLE IF NOT EXISTS fact_insumo
(
    id_aplicacion INT           NOT NULL,
    id_fecha      INT           NOT NULL,
    id_finca      VARCHAR(30)   NOT NULL,
    id_lote       DECIMAL(10,0) NOT NULL,                  -- del lote productivo o, si no hay, de la actividad
    id_variedad   DECIMAL(4,0)  NOT NULL,                  -- 0 si la aplicacion no tiene lote productivo
    id_productor  DECIMAL(10,0) NOT NULL,
    id_insumo     INT           NOT NULL,
    cantidad_base NUMERIC(14,3) NOT NULL CHECK (cantidad_base > 0),   -- cantidad * factor_base, en dim_insumo.unidad_base
    costo_total   NUMERIC(16,2) NOT NULL CHECK (costo_total >= 0),
    PRIMARY KEY(id_aplicacion),
    FOREIGN KEY(id_fecha)     REFERENCES dim_tiempo(id_fecha),
    FOREIGN KEY(id_finca)     REFERENCES dim_finca(id_finca),
    FOREIGN KEY(id_lote)      REFERENCES dim_lote(id_lote),
    FOREIGN KEY(id_variedad)  REFERENCES dim_variedad(id_variedad),
    FOREIGN KEY(id_productor) REFERENCES dim_productor(id_productor),
    FOREIGN KEY(id_insumo)    REFERENCES dim_insumo(id_insumo)
);
CREATE INDEX IF NOT EXISTS idx_fact_insumo_fecha     ON fact_insumo(id_fecha);
CREATE INDEX IF NOT EXISTS idx_fact_insumo_productor ON fact_insumo(id_productor, id_fecha);

-- Una fila por jornal (V2: tab_jornales). Costo de mano de obra.
CREATE TABLE IF NOT EXISTS fact_jornal
(
    id_jornal     INT           NOT NULL,
    id_fecha      INT           NOT NULL,                  -- fecha de la jornada
    id_finca      VARCHAR(30)   NOT NULL,                  -- 0 si el jornal no tiene lote
    id_lote       DECIMAL(10,0) NOT NULL,
    id_productor  DECIMAL(10,0) NOT NULL,                  -- quien paga
    id_trabajador INT           NOT NULL,
    labor         VARCHAR(60)   NOT NULL,
    estado_pago   VARCHAR(10)   NOT NULL CHECK (estado_pago IN ('PENDIENTE','PAGADO')),
    monto         NUMERIC(12,2) NOT NULL CHECK (monto >= 0),  -- 0 = mano vuelta
    PRIMARY KEY(id_jornal),
    FOREIGN KEY(id_fecha)      REFERENCES dim_tiempo(id_fecha),
    FOREIGN KEY(id_finca)      REFERENCES dim_finca(id_finca),
    FOREIGN KEY(id_lote)       REFERENCES dim_lote(id_lote),
    FOREIGN KEY(id_productor)  REFERENCES dim_productor(id_productor),
    FOREIGN KEY(id_trabajador) REFERENCES dim_trabajador(id_trabajador)
);
CREATE INDEX IF NOT EXISTS idx_fact_jornal_fecha     ON fact_jornal(id_fecha);
CREATE INDEX IF NOT EXISTS idx_fact_jornal_productor ON fact_jornal(id_productor, id_fecha);

-- Una fila por meta (V2: tab_meta_produccion). Al comparar con fact_cosecha:
--   - no sumar periodos que se pisan ('Anual' con 'Q1'...): filtrar por periodo;
--   - no sumar la meta global (id_variedad 0) con las metas por variedad.
CREATE TABLE IF NOT EXISTS fact_meta
(
    id_meta      INT           NOT NULL,
    id_fecha     INT           NOT NULL,                   -- primer dia del periodo
    anio         SMALLINT      NOT NULL,
    periodo      VARCHAR(10)   NOT NULL CHECK (periodo IN ('Anual','Semestre1','Semestre2','Q1','Q2','Q3','Q4')),
    id_finca     VARCHAR(30)   NOT NULL,
    id_variedad  DECIMAL(4,0)  NOT NULL,                   -- 0 = meta global de la finca
    id_productor DECIMAL(10,0) NOT NULL,
    cant_kg_meta NUMERIC(14,2) NOT NULL CHECK (cant_kg_meta > 0),
    PRIMARY KEY(id_meta),
    FOREIGN KEY(id_fecha)     REFERENCES dim_tiempo(id_fecha),
    FOREIGN KEY(id_finca)     REFERENCES dim_finca(id_finca),
    FOREIGN KEY(id_variedad)  REFERENCES dim_variedad(id_variedad),
    FOREIGN KEY(id_productor) REFERENCES dim_productor(id_productor)
);
CREATE INDEX IF NOT EXISTS idx_fact_meta_productor ON fact_meta(id_productor, anio);

-- Una fila por incidencia de plaga o enfermedad (V2: tab_incidencia_sanitaria)
CREATE TABLE IF NOT EXISTS fact_sanidad
(
    id_incidencia     INT           NOT NULL,
    id_fecha          INT           NOT NULL,              -- fecha de deteccion
    id_finca          VARCHAR(30)   NOT NULL,
    id_lote           DECIMAL(10,0) NOT NULL,
    id_variedad       DECIMAL(4,0)  NOT NULL,
    id_productor      DECIMAL(10,0) NOT NULL,
    id_plaga          SMALLINT      NOT NULL,
    nivel_afec        VARCHAR(20)   NOT NULL CHECK (nivel_afec IN ('Leve','Moderado','Severo','Critico')),
    estado            VARCHAR(20)   NOT NULL CHECK (estado IN ('activa','controlada','reincidente','cerrada')),
    cant_plantas_afec NUMERIC(10,0) NULL CHECK (cant_plantas_afec >= 0),
    PRIMARY KEY(id_incidencia),
    FOREIGN KEY(id_fecha)     REFERENCES dim_tiempo(id_fecha),
    FOREIGN KEY(id_finca)     REFERENCES dim_finca(id_finca),
    FOREIGN KEY(id_lote)      REFERENCES dim_lote(id_lote),
    FOREIGN KEY(id_variedad)  REFERENCES dim_variedad(id_variedad),
    FOREIGN KEY(id_productor) REFERENCES dim_productor(id_productor),
    FOREIGN KEY(id_plaga)     REFERENCES dim_plaga(id_plaga)
);
CREATE INDEX IF NOT EXISTS idx_fact_sanidad_fecha     ON fact_sanidad(id_fecha);
CREATE INDEX IF NOT EXISTS idx_fact_sanidad_productor ON fact_sanidad(id_productor, id_fecha);

-- Una fila por tratamiento aplicado (V2: tab_tratamiento_aplicado). costo_insumo ya esta en
-- fact_insumo: para el costo total no se suman los dos.
CREATE TABLE IF NOT EXISTS fact_tratamiento
(
    id_trat_aplic  INT           NOT NULL,
    id_incidencia  INT           NOT NULL,                 -- para cruzar con fact_sanidad (sin FK: no hay FK entre hechos)
    id_fecha       INT           NOT NULL,                 -- fecha de aplicacion
    id_finca       VARCHAR(30)   NOT NULL,
    id_lote        DECIMAL(10,0) NOT NULL,
    id_variedad    DECIMAL(4,0)  NOT NULL,
    id_productor   DECIMAL(10,0) NOT NULL,
    id_plaga       SMALLINT      NOT NULL,                 -- la plaga de la incidencia
    id_tratamiento SMALLINT      NOT NULL,
    id_insumo      INT           NOT NULL DEFAULT 0,       -- 0 = tratamiento sin insumo (cultural, mecanico)
    resultado      VARCHAR(20)   NOT NULL CHECK (resultado IN ('Efectivo','Parcial','Sin_efecto')),
    cant_plantas   NUMERIC(10,0) NOT NULL CHECK (cant_plantas >= 0),
    costo_insumo   NUMERIC(16,2) NOT NULL DEFAULT 0 CHECK (costo_insumo >= 0),
    PRIMARY KEY(id_trat_aplic),
    FOREIGN KEY(id_fecha)       REFERENCES dim_tiempo(id_fecha),
    FOREIGN KEY(id_finca)       REFERENCES dim_finca(id_finca),
    FOREIGN KEY(id_lote)        REFERENCES dim_lote(id_lote),
    FOREIGN KEY(id_variedad)    REFERENCES dim_variedad(id_variedad),
    FOREIGN KEY(id_productor)   REFERENCES dim_productor(id_productor),
    FOREIGN KEY(id_plaga)       REFERENCES dim_plaga(id_plaga),
    FOREIGN KEY(id_tratamiento) REFERENCES dim_tratamiento(id_tratamiento),
    FOREIGN KEY(id_insumo)      REFERENCES dim_insumo(id_insumo)
);
CREATE INDEX IF NOT EXISTS idx_fact_tratamiento_fecha     ON fact_tratamiento(id_fecha);
CREATE INDEX IF NOT EXISTS idx_fact_tratamiento_productor ON fact_tratamiento(id_productor, id_fecha);

-- Una fila por finca y dia (V2: tab_registro_climatico, que puede tener varias lecturas al dia:
-- la carga toma la maxima, la minima, el promedio de humedad y la suma de lluvia).
CREATE TABLE IF NOT EXISTS fact_clima
(
    id_finca         VARCHAR(30)   NOT NULL,
    id_fecha         INT           NOT NULL,
    id_productor     DECIMAL(10,0) NOT NULL,
    num_lecturas     SMALLINT      NOT NULL CHECK (num_lecturas > 0),
    temp_max_c       NUMERIC(5,2)  NULL CHECK (temp_max_c BETWEEN -10 AND 50),
    temp_min_c       NUMERIC(5,2)  NULL CHECK (temp_min_c BETWEEN -10 AND 50),
    humedad_pct      NUMERIC(5,2)  NULL CHECK (humedad_pct BETWEEN 0 AND 100),
    precipitacion_mm NUMERIC(7,2)  NULL CHECK (precipitacion_mm >= 0),
    PRIMARY KEY(id_finca, id_fecha),
    FOREIGN KEY(id_finca)     REFERENCES dim_finca(id_finca),
    FOREIGN KEY(id_fecha)     REFERENCES dim_tiempo(id_fecha),
    FOREIGN KEY(id_productor) REFERENCES dim_productor(id_productor)
);
CREATE INDEX IF NOT EXISTS idx_fact_clima_fecha     ON fact_clima(id_fecha);
CREATE INDEX IF NOT EXISTS idx_fact_clima_productor ON fact_clima(id_productor, id_fecha);

-- Una fila por analisis de suelo (V2: tab_analisis_suelo). Las medidas se promedian, no se suman.
CREATE TABLE IF NOT EXISTS fact_suelo
(
    id_analisis       INT           NOT NULL,
    id_fecha          INT           NOT NULL,              -- fecha del analisis
    id_finca          VARCHAR(30)   NOT NULL,
    id_lote           DECIMAL(10,0) NOT NULL,
    id_productor      DECIMAL(10,0) NOT NULL,
    estado_aprobacion VARCHAR(30)   NOT NULL CHECK (estado_aprobacion IN ('Pendiente','Requiere_Correccion','Apto_para_siembra','No_Apto')),
    ph_suelo          DECIMAL(4,2)  NOT NULL CHECK (ph_suelo BETWEEN 0 AND 14),
    materia_organica  DECIMAL(5,2)  NOT NULL CHECK (materia_organica BETWEEN 0 AND 100),  -- porcentaje
    fosforo_ppm       DECIMAL(8,2)  NULL CHECK (fosforo_ppm >= 0),
    potasio_meq       DECIMAL(8,2)  NULL CHECK (potasio_meq >= 0),
    calcio_meq        DECIMAL(8,2)  NULL CHECK (calcio_meq >= 0),
    magnesio_meq      DECIMAL(8,2)  NULL CHECK (magnesio_meq >= 0),
    cadmio_ppm        DECIMAL(10,4) NULL CHECK (cadmio_ppm >= 0),
    plomo_ppm         DECIMAL(10,4) NULL CHECK (plomo_ppm >= 0),
    zinc_ppm          DECIMAL(8,2)  NULL CHECK (zinc_ppm >= 0),
    cobre_ppm         DECIMAL(8,2)  NULL CHECK (cobre_ppm >= 0),
    PRIMARY KEY(id_analisis),
    FOREIGN KEY(id_fecha)     REFERENCES dim_tiempo(id_fecha),
    FOREIGN KEY(id_finca)     REFERENCES dim_finca(id_finca),
    FOREIGN KEY(id_lote)      REFERENCES dim_lote(id_lote),
    FOREIGN KEY(id_productor) REFERENCES dim_productor(id_productor)
);
CREATE INDEX IF NOT EXISTS idx_fact_suelo_productor ON fact_suelo(id_productor, id_fecha);

-- Una fila por analisis de calidad del grano (V2: tab_analisis_calidad). Porcentajes de la
-- prueba de corte: se promedian, no se suman.
CREATE TABLE IF NOT EXISTS fact_calidad
(
    id_analisis       INT           NOT NULL,
    id_cosecha        INT           NOT NULL,              -- para cruzar con fact_cosecha (sin FK: no hay FK entre hechos)
    id_fecha          INT           NOT NULL,              -- fecha del analisis
    id_finca          VARCHAR(30)   NOT NULL,
    id_lote           DECIMAL(10,0) NOT NULL,
    id_variedad       DECIMAL(4,0)  NOT NULL,
    id_productor      DECIMAL(10,0) NOT NULL,
    id_calidad        SMALLINT      NOT NULL DEFAULT 0,
    muestra_kg        NUMERIC(8,2)  NOT NULL CHECK (muestra_kg > 0),
    granos_sanos      DECIMAL(5,2)  NULL CHECK (granos_sanos      BETWEEN 0 AND 100),
    granos_ferment    DECIMAL(5,2)  NULL CHECK (granos_ferment    BETWEEN 0 AND 100),
    granos_violetas   DECIMAL(5,2)  NULL CHECK (granos_violetas   BETWEEN 0 AND 100),
    granos_pizarrosos DECIMAL(5,2)  NULL CHECK (granos_pizarrosos BETWEEN 0 AND 100),
    granos_mohosos    DECIMAL(5,2)  NULL CHECK (granos_mohosos    BETWEEN 0 AND 100),
    granos_germinad   DECIMAL(5,2)  NULL CHECK (granos_germinad   BETWEEN 0 AND 100),
    humedad_pct       DECIMAL(5,2)  NULL CHECK (humedad_pct       BETWEEN 0 AND 100),
    indice_ferment    DECIMAL(5,2)  NULL CHECK (indice_ferment >= 0),
    PRIMARY KEY(id_analisis),
    FOREIGN KEY(id_fecha)     REFERENCES dim_tiempo(id_fecha),
    FOREIGN KEY(id_finca)     REFERENCES dim_finca(id_finca),
    FOREIGN KEY(id_lote)      REFERENCES dim_lote(id_lote),
    FOREIGN KEY(id_variedad)  REFERENCES dim_variedad(id_variedad),
    FOREIGN KEY(id_productor) REFERENCES dim_productor(id_productor),
    FOREIGN KEY(id_calidad)   REFERENCES dim_calidad(id_calidad)
);
CREATE INDEX IF NOT EXISTS idx_fact_calidad_productor ON fact_calidad(id_productor, id_fecha);

