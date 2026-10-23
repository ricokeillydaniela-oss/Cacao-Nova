DROP TABLE IF EXISTS tab_inventario_insumos;   --HECHO
DROP TABLE IF EXISTS tab_jornales;              --HECHO
DROP TABLE IF EXISTS tab_ventas;  --HECHO             
DROP TABLE IF EXISTS tab_inventario_bodega; --HECHO
DROP TABLE IF EXISTS tab_secado; --HECHO
DROP TABLE IF EXISTS tab_fermentacion; --HECHO
DROP TABLE IF EXISTS tab_recoleccion; --HECHO
DROP TABLE IF EXISTS tab_monitoreo_plaga_det; --DIMENSION
DROP TABLE IF EXISTS tab_tratamiento_aplicado;
DROP TABLE IF EXISTS tab_incidencia_sanitaria;   --DIMENSIÓN
DROP TABLE IF EXISTS tab_monitoreo_periodico;
DROP TABLE IF EXISTS tab_catalogo_insumo;       --DIMENSIÓN
DROP TABLE IF EXISTS tab_catalogo_plaga;  --DIMENSIÓN
DROP TABLE IF EXISTS tab_cosecha;
DROP TABLE IF EXISTS tab_monitoreo_siembra; --HECHOS
DROP TABLE IF EXISTS tab_siembra; --HECHO
DROP TABLE IF EXISTS tab_lote_productivo; --DIMENSIÓN
DROP TABLE IF EXISTS tab_analisis_suelo; --HECHO
DROP TABLE IF EXISTS tab_preparacion_lotes;
DROP TABLE IF EXISTS tab_actividades;           --ACTIVIDADES
DROP TABLE IF EXISTS tab_lotes;
DROP TABLE IF EXISTS tab_catalogo_variedad;
DROP TABLE IF EXISTS tab_finca;                 --DIMENSIÓN 
DROP TABLE IF EXISTS tab_personas; 
DROP TABLE IF EXISTS tab_ciudades; --Dimensional pendiente si se elimina o no

 
CREATE TABLE IF NOT EXISTS tab_ciudades
(
    id_ciudad  VARCHAR(5)  NOT NULL,                -- codigo DANE del municipio
    id_dpto    VARCHAR(2)  NOT NULL,
    PRIMARY KEY(id_ciudad),
    UNIQUE(nom_ciudad, id_dpto),
    CHECK (id_ciudad ~ '^[0-9]{5}$' AND LEFT(id_ciudad, 2) = id_dpto),  -- DANE: el municipio empieza por su departamento
    FOREIGN KEY(id_dpto) REFERENCES tab_dptos(id_dpto)
);

CREATE TABLE IF NOT EXISTS tab_personas
(
    id_persona          DECIMAL(10,0) NOT NULL CHECK (id_persona > 0),   -- numero de documento
    id_ciudad           VARCHAR(5)    NOT NULL,
    ind_doc             VARCHAR(3)    NOT NULL CHECK (ind_doc IN ('CC','CE','NIT','TI')),
    nom_apell_persona   VARCHAR(100)  NOT NULL 
);

CREATE TABLE IF NOT EXISTS tab_finca
(
    id_finca      VARCHAR(30)   NOT NULL CHECK (BTRIM(id_finca) <> ''),
    nom_finca     VARCHAR(120)  NOT NULL CHECK (BTRIM(nom_finca) <> ''),
    hect_cacao    DECIMAL(10,2) NOT NULL CHECK (hect_cacao >= 0),

    PRIMARY KEY(id_finca),
    FOREIGN KEY(id_ciudad)  REFERENCES tab_ciudades(id_ciudad),
);

CREATE TABLE IF NOT EXISTS tab_catalogo_variedad
(
    id_variedad   DECIMAL(4,0)  NOT NULL CHECK (id_variedad > 0),
    ind_tamano    VARCHAR(60)   NOT NULL CHECK (BTRIM(ind_tamano) <> ''),
    rend_promedio DECIMAL(10,2) CHECK (rend_promedio IS NULL OR rend_promedio >= 0),
    PRIMARY KEY(id_variedad)
);

CREATE TABLE IF NOT EXISTS tab_lotes
(
    id_lote        DECIMAL(10,0)  NOT NULL CHECK (id_lote > 0),
    id_finca       VARCHAR(30)   NOT NULL CHECK
    nom_lote       VARCHAR(100)   NOT NULL CHECK (BTRIM(nom_lote) <> ''),
    area_hecta     DECIMAL(10,2)  NOT NULL CHECK (area_hecta > 0)
    PRIMARY KEY(id_lote),
    UNIQUE(id_finca, nom_lote), -- Evita dos lotes con el mismo nombre en una misma finca
    FOREIGN KEY(id_finca) REFERENCES tab_finca(id_finca) ON DELETE RESTRICT
);

CREATE TABLE IF NOT EXISTS tab_actividades
(
    id_actividad      INT GENERATED ALWAYS AS IDENTITY,
    id_lote           DECIMAL(10,0) NULL,
    nom_actividad     VARCHAR(120)  NOT NULL CHECK 
    PRIMARY KEY(id_actividad),
    FOREIGN KEY(id_lote)        REFERENCES tab_lotes(id_lote) ON DELETE RESTRICT,
);


CREATE TABLE IF NOT EXISTS tab_preparacion_lotes
(
    id_preparacion    INT GENERATED ALWAYS AS IDENTITY,
    id_lote           DECIMAL(10,0) NOT NULL,
    tipo_abono_inicial VARCHAR(100) NULL,     -- Abono usado en la preparación
    PRIMARY KEY(id_preparacion),
    FOREIGN KEY(id_persona) REFERENCES tab_personas(id_persona) ON DELETE RESTRICT,
    FOREIGN KEY(id_lote)    REFERENCES tab_lotes(id_lote)
);

CREATE TABLE IF NOT EXISTS tab_analisis_suelo
(
    id_analisis        INT GENERATED ALWAYS AS IDENTITY,
    ph_suelo           DECIMAL(4,2)  NOT NULL CHECK (ph_suelo BETWEEN 0 AND 14),
    cadmio_ppm         DECIMAL(10,4) NULL,     -- V2: 4 decimales, el cadmio se mide en milesimas de ppm
    PRIMARY KEY(id_analisis),                                                                                                                                                                                                       
    CHECK ((cadmio_ppm IS NULL OR cadmio_ppm >= 0) AND (plomo_ppm IS NULL OR plomo_ppm >= 0)),
    CHECK (fecha_listo IS NULL OR fecha_listo >= fecha_analisis),
    CONSTRAINT fk_analisis_prep FOREIGN KEY(id_preparacion) REFERENCES tab_preparacion_lotes(id_preparacion) ON DELETE RESTRICT ON UPDATE RESTRICT
);

CREATE TABLE IF NOT EXISTS tab_lote_productivo
(
    id_lot_prod       INT GENERATED ALWAYS AS IDENTITY,
    id_analisis       INT           NOT NULL, -- <--- Conexión al análisis químico que dio el OK
    id_variedad       DECIMAL(4,0)  NOT NULL,
    fecha_plantacion  DATE          NOT NULL CHECK (fecha_plantacion >= DATE '1950-01-01'),
    PRIMARY KEY(id_lot_prod),
    CONSTRAINT fk_prod_analisis FOREIGN KEY(id_analisis) REFERENCES tab_analisis_suelo(id_analisis) ON DELETE RESTRICT ON UPDATE RESTRICT,
    CONSTRAINT fk_prod_variedad FOREIGN KEY(id_variedad) REFERENCES tab_catalogo_variedad(id_variedad) ON DELETE RESTRICT ON UPDATE RESTRICT
);

CREATE TABLE IF NOT EXISTS tab_siembra
(
    id_siembra          INT GENERATED ALWAYS AS IDENTITY,
    id_actividad        INT NOT NULL,
    cant_planta         DECIMAL(8,0)  NOT NULL CHECK (cant_planta > 0),
    fech_inicio         DATE          NOT NULL CHECK (fech_inicio >= DATE '1950-01-01'),
    PRIMARY KEY(id_siembra),
    UNIQUE(id_actividad),                         -- una siembra por actividad
    FOREIGN KEY(id_actividad) REFERENCES tab_actividades(id_actividad) ON DELETE RESTRICT
);

--ESTA TABLA ES NETAMENTE PARA EL MONITOREO DE LA SIEMBRA, NO PARA OTRAS ACTIVIDADES (CUANDO SE TRASPLANTA LA PLÁNTULA)
CREATE TABLE IF NOT EXISTS tab_monitoreo_siembra
(
    id_monit_siemb INT GENERATED ALWAYS AS IDENTITY,
    id_siembra     INT NOT NULL,
    plant_perdid   DECIMAL(8,0)  NOT NULL CHECK (plant_perdid >= 0),
    plant_enferm   DECIMAL(8,0)  NOT NULL CHECK (plant_enferm >= 0),
   
    PRIMARY KEY(id_monit_siemb),
    FOREIGN KEY(id_siembra) REFERENCES tab_siembra(id_siembra)
);

CREATE TABLE IF NOT EXISTS tab_cosecha
(
    id_cosecha       INT GENERATED ALWAYS AS IDENTITY,
    id_lot_prod      INT NOT NULL,
    peso_kg          NUMERIC(12,2) NOT NULL CHECK (peso_kg > 0),  -- siempre en kg (V1 podia tener arrobas aqui)

    PRIMARY KEY(id_cosecha),
    FOREIGN KEY(id_lot_prod)    REFERENCES tab_lote_productivo(id_lot_prod),

);


CREATE TABLE IF NOT EXISTS tab_catalogo_plaga
 (
    id_plaga        SMALLINT     NOT NULL CHECK (id_plaga > 0),
    nom_plaga       VARCHAR(100) NOT NULL UNIQUE CHECK (BTRIM(nom_plaga) <> ''),
    tip_agente      VARCHAR(20)  NOT NULL CHECK (tip_agente IN ('Hongo','Bacteria','Insecto','Acaro','Virus','Otro'))

    PRIMARY KEY (id_plaga)
);

CREATE TABLE IF NOT EXISTS tab_catalogo_insumo
(
    id_insumo             INT GENERATED ALWAYS AS IDENTITY,
    nom_insumo            VARCHAR(100)  NOT NULL CHECK (BTRIM(nom_insumo) <> ''),
    tip_insumo            VARCHAR(20)   NOT NULL CHECK (tip_insumo IN ('Fertilizante','Fungicida','Insecticida','Herbicida','Enmienda','Bioinsumo','Semilla','Otro')),
    PRIMARY KEY(id_insumo),
    FOREIGN KEY(id_unidad) REFERENCES tab_unidad_medida(id_unidad) ON DELETE RESTRICT ON UPDATE RESTRICT
);

-- V2: el monitoreo cuelga del lote productivo 
CREATE TABLE IF NOT EXISTS tab_monitoreo_periodico
(
    id_monit_period INT GENERATED ALWAYS AS IDENTITY,
    id_lot_prod     INT NOT NULL,
    fech_inspec     DATE          NOT NULL CHECK (fech_inspec >= DATE '1950-01-01'),
    PRIMARY KEY(id_monit_period),
    FOREIGN KEY(id_lot_prod) REFERENCES tab_lote_productivo(id_lot_prod) ON DELETE RESTRICT ON UPDATE RESTRICT,
);

CREATE TABLE IF NOT EXISTS tab_incidencia_sanitaria
(
    id_incidencia   INT GENERATED ALWAYS AS IDENTITY,
    id_lot_prod     INT NOT NULL,                 -- puede detectarse fuera de un monitoreo
    id_plaga        SMALLINT      NOT NULL,
    fec_deteccion   DATE          NOT NULL DEFAULT CURRENT_DATE CHECK (fec_deteccion >= DATE '1950-01-01'),
    cant_plantas_afec NUMERIC(10,0) NULL CHECK (cant_plantas_afec >= 0),  -- numero de plantas
    PRIMARY KEY (id_incidencia),
    FOREIGN KEY (id_plaga)        REFERENCES tab_catalogo_plaga(id_plaga),
    FOREIGN KEY (id_lot_prod)     REFERENCES tab_lote_productivo(id_lot_prod)
);

CREATE TABLE IF NOT EXISTS tab_tratamiento_aplicado
(
    id_trat_aplic        INT GENERATED ALWAYS AS IDENTITY,
    id_incidencia        INT NOT NULL,
    id_lot_prod          INT NULL,     -- opcional para asociar plagas comunes a ciertos lotes/productores
    id_aplicacion_insumo INT           NULL,     -- V2: el insumo aplicado (V1: id_insumo)
    fec_aplicacion       DATE          NOT NULL CHECK (fec_aplicacion >= DATE '1950-01-01'),
    dosis                VARCHAR(60)   NOT NULL CHECK (BTRIM(dosis) <> ''),        -- ej. '2 L/ha', '500 g/árbol'
    PRIMARY KEY (id_trat_aplic),
    UNIQUE(uuid_registro),
    FOREIGN KEY (id_incidencia)        REFERENCES tab_incidencia_sanitaria(id_incidencia),
    FOREIGN KEY (id_aplicacion_insumo) REFERENCES tab_aplicacion_insumo(id_aplicacion) ON DELETE RESTRICT ON UPDATE RESTRICT,
    FOREIGN KEY (id_lot_prod)          REFERENCES tab_lote_productivo(id_lot_prod)
);

CREATE TABLE IF NOT EXISTS tab_monitoreo_plaga_det
(
    id_mon_det      INT GENERATED ALWAYS AS IDENTITY,
    id_trat_aplic   INT NOT NULL,

    PRIMARY KEY (id_mon_det),
    FOREIGN KEY (id_trat_aplic) REFERENCES tab_tratamiento_aplicado(id_trat_aplic)
);

CREATE TABLE IF NOT EXISTS tab_recoleccion
(
    id_recoleccion    INT GENERATED ALWAYS AS IDENTITY,
    id_cosecha        INT NOT NULL, -- Vinculación directa al origen
    fecha_recoleccion DATE          NOT NULL CHECK (fecha_recoleccion >= DATE '1950-01-01'),
    peso_entrada_kg   NUMERIC(12,2) NOT NULL CHECK (peso_entrada_kg > 0), -- V1: cantidad_entrada + unidad_medida
    PRIMARY KEY(id_recoleccion),
    FOREIGN KEY(id_cosecha) REFERENCES tab_cosecha(id_cosecha) ON DELETE RESTRICT,

);

CREATE TABLE IF NOT EXISTS tab_fermentacion
(
    id_fermentacion   INT GENERATED ALWAYS AS IDENTITY,
    id_recoleccion    INT NOT NULL, -- Cadena estricta
    fecha_inicio      DATE          NOT NULL CHECK (fecha_inicio >= DATE '1950-01-01'),
    fecha_fin         DATE          NULL,
    peso_salida_kg    NUMERIC(12,2) NULL CHECK (peso_salida_kg IS NULL OR peso_salida_kg > 0),
    volteos_realizados DECIMAL(3,0) NOT NULL DEFAULT 0 CHECK (volteos_realizados >= 0),
    temp_maxima_c     NUMERIC(5,2)  NULL CHECK (temp_maxima_c IS NULL OR temp_maxima_c BETWEEN 0 AND 70), -- V2
    PRIMARY KEY(id_fermentacion),
    UNIQUE(id_recoleccion), -- 1 Recolección = 1 Fermentación
    UNIQUE(uuid_registro),
    FOREIGN KEY(id_recoleccion) REFERENCES tab_recoleccion(id_recoleccion) ON DELETE RESTRICT ON UPDATE RESTRICT, -- V1: CASCADE

    CHECK (fecha_fin IS NULL OR fecha_fin >= fecha_inicio)
);

CREATE TABLE IF NOT EXISTS tab_secado
(
    id_secado         INT GENERATED ALWAYS AS IDENTITY,
    id_fermentacion   INT NOT NULL, -- Cadena estricta
    id_persona        DECIMAL(10,0) NOT NULL, -- Responsable
    peso_salida_kg    NUMERIC(12,2) NULL CHECK (peso_salida_kg > 0),
    humedad_final_pct DECIMAL(5,2)  NULL CHECK (humedad_final_pct BETWEEN 5.0 AND 12.0), -- V2: se conoce al terminar
    PRIMARY KEY(id_secado),
    UNIQUE(id_fermentacion), -- 1 Fermentación = 1 Secado
    UNIQUE(uuid_registro),
    CHECK (fecha_fin IS NULL OR humedad_final_pct IS NOT NULL), -- al cerrar el secado la humedad es obligatoria
    FOREIGN KEY(id_fermentacion) REFERENCES tab_fermentacion(id_fermentacion) ON DELETE RESTRICT ON UPDATE RESTRICT, -- V1: CASCADE
    FOREIGN KEY(id_persona) REFERENCES tab_personas(id_persona) ON DELETE RESTRICT
);
CREATE INDEX IF NOT EXISTS idx_secado_persona ON tab_secado(id_persona);

--*******************************************************************
-- BODEGA Y VENTA EN GRANO


CREATE INDEX IF NOT EXISTS idx_bodega_finca ON tab_bodega(id_finca);

-- Lote de grano guardado en bodega. Es lo que se vende.
CREATE TABLE IF NOT EXISTS tab_inventario_bodega
(
    id_inventario  INT GENERATED ALWAYS AS IDENTITY,
    id_bodega      INT           NOT NULL,
    cant_kg_actual NUMERIC(12,2) NOT NULL CHECK (cant_kg_actual >= 0 AND cant_kg_actual <= cant_kg_ingres), -- lo descuenta tab_venta_detalle
    PRIMARY KEY(id_inventario),
    FOREIGN KEY(id_bodega)  REFERENCES tab_bodega(id_bodega),
);

CREATE TABLE IF NOT EXISTS tab_ventas
(
    id_venta      INT GENERATED ALWAYS AS IDENTITY,
    cant_kg       NUMERIC(12,2)  NOT NULL CHECK (cant_kg > 0),
    precio_kg     NUMERIC(12,2)  NOT NULL CHECK (precio_kg > 0),
    valor_total   NUMERIC(16,2)  NOT NULL CHECK (valor_total > 0),
    PRIMARY KEY(id_venta),
    CHECK (ABS(valor_total - cant_kg * precio_kg) <= cant_kg * 0.005 + 0.01), -- el total y el precio por kg no se contradicen
    FOREIGN KEY(id_persona) REFERENCES tab_productor(id_persona)
);

CREATE TABLE IF NOT EXISTS tab_jornales
(
    id_jornal       INT GENERATED ALWAYS AS IDENTITY,
    trabajador      VARCHAR(120)   NOT NULL CHECK (BTRIM(trabajador) <> ''), --EN EL MODELO PRINCIPAL CAMBIÉ ESTE ROL,HAY QUE REFERENCIARLO
    monto           NUMERIC(12,2)  NOT NULL CHECK (monto >= 0),  -- 0 admitido: mano vuelta (trabajo de intercambio)
    estado          VARCHAR(10)    NOT NULL DEFAULT 'PENDIENTE' CHECK (estado IN ('PENDIENTE','PAGADO')),
    fecha_pago      DATE           NULL,+
    CHECK ((estado = 'PENDIENTE' AND fecha_pago IS NULL AND metodo_pago IS NULL AND referencia_pago IS NULL)  -- pendiente: sin datos de pago
        OR (estado = 'PAGADO' AND fecha_pago IS NOT NULL)),                                                -- pagado: con fecha de pago
    PRIMARY KEY(id_jornal),
    FOREIGN KEY(id_persona) REFERENCES tab_personas(id_persona) ON DELETE RESTRICT,
    FOREIGN KEY(id_lote)    REFERENCES tab_lotes(id_lote) ON DELETE RESTRICT ON UPDATE RESTRICT
);

-- Bodega de insumos (fertilizantes, fungicidas, herramientas) del módulo Inventario del dashboard
CREATE TABLE IF NOT EXISTS tab_inventario_insumos
(
    id_inventario  INT GENERATED ALWAYS AS IDENTITY, --RREVISAR NOMBRE DE PK
    nombre         VARCHAR(100)  NOT NULL CHECK (BTRIM(nombre) <> ''),
    categoria      VARCHAR(60)   NOT NULL CHECK (BTRIM(categoria) <> ''),
    cantidad       NUMERIC(10,2) NOT NULL CHECK (cantidad >= 0),
    PRIMARY KEY(id_inventario),
    UNIQUE(uuid_registro),
    FOREIGN KEY(id_persona) REFERENCES tab_personas(id_persona) ON DELETE RESTRICT
);
