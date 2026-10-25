--
-- PostgreSQL database dump
--

\restrict pLvDk6eGbr7sM932sj3ogdKTHSjvuyrS72TmL5I7QnTrAhhZXCxFqV8sB2H4Nfi

-- Dumped from database version 18.6 (Ubuntu 18.6-0ubuntu0.26.04.1)
-- Dumped by pg_dump version 18.6 (Ubuntu 18.6-0ubuntu0.26.04.1)

SET statement_timeout = 0;
SET lock_timeout = 0;
SET idle_in_transaction_session_timeout = 0;
SET transaction_timeout = 0;
SET client_encoding = 'UTF8';
SET standard_conforming_strings = on;
SELECT pg_catalog.set_config('search_path', '', false);
SET check_function_bodies = false;
SET xmloption = content;
SET client_min_messages = warning;
SET row_security = off;

--
-- Name: public; Type: SCHEMA; Schema: -; Owner: -
--

CREATE SCHEMA public;


--
-- Name: SCHEMA public; Type: COMMENT; Schema: -; Owner: -
--

COMMENT ON SCHEMA public IS 'standard public schema';


--
-- Name: fn_autoaudit_generica(); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.fn_autoaudit_generica() RETURNS trigger
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO 'pg_catalog', 'pg_temp'
    AS $$
DECLARE
    v_id_tabla       bigint;
    v_id_evento      bigint;
    v_id_usuario     bigint;
    v_id_bitacora    bigint;
    v_registro_id    text;
    v_old            jsonb;
    v_new            jsonb;
    v_fila           jsonb;
    v_pk_cols        text[];
    v_columna        record;
BEGIN
    -- Los datos de OLD y NEW dependen del tipo de operacion.
    IF TG_OP = 'INSERT' THEN
        v_old := '{}'::jsonb;
        v_new := to_jsonb(NEW);
    ELSIF TG_OP = 'DELETE' THEN
        v_old := to_jsonb(OLD);
        v_new := '{}'::jsonb;
    ELSE
        v_old := to_jsonb(OLD);
        v_new := to_jsonb(NEW);
    END IF;

    -- Solo auditar tablas registradas y activas.
    SELECT t.id_tabla
      INTO v_id_tabla
      FROM public.tablas_auditadas AS t
     WHERE t.esquema = TG_TABLE_SCHEMA
       AND t.nombre_tabla = TG_TABLE_NAME
       AND t.activa IS TRUE;

    IF NOT FOUND THEN
        IF TG_OP = 'DELETE' THEN RETURN OLD; END IF;
        RETURN NEW;
    END IF;

    -- Localizar el evento (INSERT / UPDATE / DELETE) por nombre, no por ID fijo.
    SELECT e.id_evento
      INTO v_id_evento
      FROM public.eventos_auditoria AS e
     WHERE e.nombre_evento = TG_OP;

    IF NOT FOUND THEN
        IF TG_OP = 'DELETE' THEN RETURN OLD; END IF;
        RETURN NEW;
    END IF;

    -- Buscar el usuario que inicio la sesion, si esta registrado.
    SELECT u.id_usuario
      INTO v_id_usuario
      FROM public.usuarios_auditados AS u
     WHERE u.nombre_usuario = session_user
       AND u.activo IS TRUE;

    -- Identificar el registro segun su clave primaria, si existe.
    -- Admite claves simples y compuestas. Sin clave primaria, guarda NULL.
    SELECT array_agg(a.attname::text ORDER BY k.ord)
      INTO v_pk_cols
      FROM pg_catalog.pg_index AS i
      JOIN LATERAL unnest(i.indkey) WITH ORDINALITY AS k(attnum, ord)
        ON true
      JOIN pg_catalog.pg_attribute AS a
        ON a.attrelid = i.indrelid
       AND a.attnum = k.attnum
     WHERE i.indrelid = TG_RELID
       AND i.indisprimary
       AND k.ord <= i.indnkeyatts;

    IF TG_OP = 'DELETE' THEN
        v_fila := v_old;
    ELSE
        v_fila := v_new;
    END IF;

    IF coalesce(array_length(v_pk_cols, 1), 0) = 1 THEN
        v_registro_id := v_fila ->> v_pk_cols[1];
    ELSIF coalesce(array_length(v_pk_cols, 1), 0) > 1 THEN
        SELECT jsonb_object_agg(p.col, v_fila -> p.col)::text
          INTO v_registro_id
          FROM unnest(v_pk_cols) AS p(col);
    END IF;

    -- Registrar solo columnas habilitadas para este evento.
    -- En UPDATE se registran unicamente columnas cuyo valor haya cambiado.
    FOR v_columna IN
        SELECT c.id_columna, c.nombre_columna
          FROM public.columnas_auditadas AS c
          JOIN public.configuracion_auditoria AS cfg
            ON cfg.id_columna = c.id_columna
         WHERE c.id_tabla = v_id_tabla
           AND c.activa IS TRUE
           AND cfg.id_evento = v_id_evento
           AND cfg.activa IS TRUE
         ORDER BY c.id_columna
    LOOP
        -- Ignorar una configuracion que ya no corresponda a una columna real.
        IF NOT (v_old ? v_columna.nombre_columna OR
                v_new ? v_columna.nombre_columna) THEN
            CONTINUE;
        END IF;

        IF TG_OP = 'UPDATE'
           AND (v_old -> v_columna.nombre_columna)
               IS NOT DISTINCT FROM (v_new -> v_columna.nombre_columna) THEN
            CONTINUE;
        END IF;

        -- Crear una unica cabecera por operacion, solamente si hubo algo que auditar.
        IF v_id_bitacora IS NULL THEN
            INSERT INTO public.bitacora_auditoria
                (id_tabla, id_evento, id_usuario, registro_id, ip_origen)
            VALUES
                (v_id_tabla, v_id_evento, v_id_usuario, v_registro_id, inet_client_addr())
            RETURNING id_bitacora INTO v_id_bitacora;
        END IF;

        INSERT INTO public.detalle_bitacora
            (id_bitacora, id_columna, valor_anterior, valor_nuevo)
        VALUES
            (v_id_bitacora,
             v_columna.id_columna,
             CASE WHEN TG_OP = 'INSERT' THEN NULL
                  ELSE v_old ->> v_columna.nombre_columna END,
             CASE WHEN TG_OP = 'DELETE' THEN NULL
                  ELSE v_new ->> v_columna.nombre_columna END);
    END LOOP;

    IF TG_OP = 'DELETE' THEN RETURN OLD; END IF;
    RETURN NEW;
END;
$$;


--
-- Name: fn_prueba_auditoria(); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.fn_prueba_auditoria() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
DECLARE
    v_bitacora BIGINT;
BEGIN
    IF OLD.telefono IS DISTINCT FROM NEW.telefono
       AND EXISTS (
           SELECT 1
             FROM public.configuracion_auditoria
            WHERE id_columna = 1
              AND id_evento = 2
              AND activa = TRUE
       )
    THEN
        INSERT INTO public.bitacora_auditoria
            (id_tabla, id_evento, id_usuario, registro_id)
        VALUES (1, 2, 1, NEW.id_cliente::text)
        RETURNING id_bitacora INTO v_bitacora;

        INSERT INTO public.detalle_bitacora
            (id_bitacora, id_columna, valor_anterior, valor_nuevo)
        VALUES (v_bitacora, 1, OLD.telefono, NEW.telefono);
    END IF;

    RETURN NEW;
END;
$$;


--
-- Name: fn_sincronizar_triggers_autoaudit(); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.fn_sincronizar_triggers_autoaudit() RETURNS TABLE(esquema text, tabla text, resultado text)
    LANGUAGE plpgsql
    AS $$
DECLARE
    v_t record;
    v_relid oid;
    v_invalidas text;
BEGIN
    -- La DDL requiere que quien ejecute esta función tenga permiso
    -- para administrar triggers de las tablas fuente (por ejemplo, su propietario).
    FOR v_t IN
        SELECT t.id_tabla, t.esquema, t.nombre_tabla
          FROM public.tablas_auditadas AS t
         WHERE t.activa IS TRUE
         ORDER BY t.id_tabla
    LOOP
        -- Resolver exclusivamente tablas existentes de esquema y nombre precisos.
        SELECT c.oid
          INTO v_relid
          FROM pg_catalog.pg_class AS c
          JOIN pg_catalog.pg_namespace AS ns ON ns.oid = c.relnamespace
         WHERE ns.nspname = v_t.esquema
           AND c.relname = v_t.nombre_tabla
           AND c.relkind = 'r';

        IF v_relid IS NULL THEN
            RETURN QUERY SELECT v_t.esquema::text, v_t.nombre_tabla::text,
                                'OMITIDA: tabla de origen inexistente/no ordinaria'::text;
            CONTINUE;
        END IF;

        -- Solo tablas que tengan por lo menos una regla activa.
        IF NOT EXISTS (
            SELECT 1
              FROM public.columnas_auditadas AS col
              JOIN public.configuracion_auditoria AS cfg ON cfg.id_columna = col.id_columna
              JOIN public.eventos_auditoria AS ev ON ev.id_evento = cfg.id_evento
             WHERE col.id_tabla = v_t.id_tabla
               AND col.activa IS TRUE
               AND cfg.activa IS TRUE
               AND ev.nombre_evento IN ('INSERT','UPDATE','DELETE')
        ) THEN
            RETURN QUERY SELECT v_t.esquema::text, v_t.nombre_tabla::text,
                                'OMITIDA: no existen reglas de auditoria activas'::text;
            CONTINUE;
        END IF;

        -- No instalar el trigger si la configuración tiene columnas inexistentes.
        SELECT string_agg(col.nombre_columna, ', ' ORDER BY col.nombre_columna)
          INTO v_invalidas
          FROM public.columnas_auditadas AS col
          JOIN public.configuracion_auditoria AS cfg ON cfg.id_columna = col.id_columna
         WHERE col.id_tabla = v_t.id_tabla
           AND col.activa IS TRUE
           AND cfg.activa IS TRUE
           AND NOT EXISTS (
               SELECT 1 FROM pg_catalog.pg_attribute AS a
                WHERE a.attrelid = v_relid
                  AND a.attname = col.nombre_columna
                  AND a.attnum > 0 AND NOT a.attisdropped
           );

        IF v_invalidas IS NOT NULL THEN
            RETURN QUERY SELECT v_t.esquema::text, v_t.nombre_tabla::text,
                                ('OMITIDA: columnas inexistentes: ' || v_invalidas)::text;
            CONTINUE;
        END IF;

        -- Identificadores correctamente citados (no concatenar nombres sin format %I).
        -- Un trigger AFTER por tabla, que solo registra eventos configurados
        -- porque fn_autoaudit_generica() consulta configuracion_auditoria.
        EXECUTE format(
            'CREATE OR REPLACE TRIGGER trg_autoaudit '
            || 'AFTER INSERT OR UPDATE OR DELETE ON %I.%I '
            || 'FOR EACH ROW EXECUTE FUNCTION public.fn_autoaudit_generica()',
            v_t.esquema, v_t.nombre_tabla
        );

        RETURN QUERY SELECT v_t.esquema::text, v_t.nombre_tabla::text,
                            'INSTALADO/ACTUALIZADO'::text;
    END LOOP;
END;
$$;


SET default_tablespace = '';

SET default_table_access_method = heap;

--
-- Name: bitacora_auditoria; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.bitacora_auditoria (
    id_bitacora bigint NOT NULL,
    id_tabla bigint NOT NULL,
    id_evento bigint NOT NULL,
    id_usuario bigint,
    id_estacion bigint,
    registro_id text,
    fecha_evento timestamp with time zone DEFAULT now(),
    ip_origen inet
);


--
-- Name: bitacora_auditoria_id_bitacora_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.bitacora_auditoria_id_bitacora_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: bitacora_auditoria_id_bitacora_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.bitacora_auditoria_id_bitacora_seq OWNED BY public.bitacora_auditoria.id_bitacora;


--
-- Name: cliente_prueba; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.cliente_prueba (
    id_cliente bigint NOT NULL,
    nombre character varying(100),
    telefono character varying(20)
);


--
-- Name: cliente_prueba_id_cliente_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.cliente_prueba_id_cliente_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: cliente_prueba_id_cliente_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.cliente_prueba_id_cliente_seq OWNED BY public.cliente_prueba.id_cliente;


--
-- Name: columnas_auditadas; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.columnas_auditadas (
    id_columna bigint NOT NULL,
    id_tabla bigint NOT NULL,
    nombre_columna character varying(63) NOT NULL,
    activa boolean DEFAULT true
);


--
-- Name: columnas_auditadas_id_columna_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.columnas_auditadas_id_columna_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: columnas_auditadas_id_columna_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.columnas_auditadas_id_columna_seq OWNED BY public.columnas_auditadas.id_columna;


--
-- Name: configuracion_auditoria; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.configuracion_auditoria (
    id_config bigint NOT NULL,
    id_columna bigint NOT NULL,
    id_evento bigint NOT NULL,
    activa boolean DEFAULT true
);


--
-- Name: configuracion_auditoria_id_config_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.configuracion_auditoria_id_config_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: configuracion_auditoria_id_config_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.configuracion_auditoria_id_config_seq OWNED BY public.configuracion_auditoria.id_config;


--
-- Name: detalle_bitacora; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.detalle_bitacora (
    id_detalle bigint NOT NULL,
    id_bitacora bigint NOT NULL,
    id_columna bigint NOT NULL,
    valor_anterior text,
    valor_nuevo text
);


--
-- Name: detalle_bitacora_id_detalle_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.detalle_bitacora_id_detalle_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: detalle_bitacora_id_detalle_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.detalle_bitacora_id_detalle_seq OWNED BY public.detalle_bitacora.id_detalle;


--
-- Name: estaciones_trabajo; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.estaciones_trabajo (
    id_estacion bigint NOT NULL,
    nombre_equipo character varying(100),
    ip_origen inet,
    fecha_registro timestamp without time zone DEFAULT now()
);


--
-- Name: estaciones_trabajo_id_estacion_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.estaciones_trabajo_id_estacion_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: estaciones_trabajo_id_estacion_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.estaciones_trabajo_id_estacion_seq OWNED BY public.estaciones_trabajo.id_estacion;


--
-- Name: eventos_auditoria; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.eventos_auditoria (
    id_evento bigint NOT NULL,
    nombre_evento character varying(10) NOT NULL,
    descripcion character varying(100)
);


--
-- Name: eventos_auditoria_id_evento_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.eventos_auditoria_id_evento_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: eventos_auditoria_id_evento_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.eventos_auditoria_id_evento_seq OWNED BY public.eventos_auditoria.id_evento;


--
-- Name: productos_prueba; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.productos_prueba (
    id_producto bigint NOT NULL,
    nombre character varying(100),
    precio numeric(10,2)
);


--
-- Name: productos_prueba_id_producto_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.productos_prueba_id_producto_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: productos_prueba_id_producto_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.productos_prueba_id_producto_seq OWNED BY public.productos_prueba.id_producto;


--
-- Name: tablas_auditadas; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.tablas_auditadas (
    id_tabla bigint NOT NULL,
    esquema character varying(63) NOT NULL,
    nombre_tabla character varying(63) NOT NULL,
    activa boolean DEFAULT true,
    fecha_creacion timestamp without time zone DEFAULT now()
);


--
-- Name: usuarios_auditados; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.usuarios_auditados (
    id_usuario bigint NOT NULL,
    nombre_usuario character varying(63) NOT NULL,
    activo boolean DEFAULT true
);


--
-- Name: reporte_autoaudit; Type: VIEW; Schema: public; Owner: -
--

CREATE VIEW public.reporte_autoaudit AS
 SELECT b.id_bitacora,
    t.nombre_tabla,
    e.nombre_evento,
    u.nombre_usuario,
    c.nombre_columna,
    d.valor_anterior,
    d.valor_nuevo,
    b.fecha_evento
   FROM (((((public.bitacora_auditoria b
     JOIN public.tablas_auditadas t ON ((b.id_tabla = t.id_tabla)))
     JOIN public.eventos_auditoria e ON ((b.id_evento = e.id_evento)))
     LEFT JOIN public.usuarios_auditados u ON ((b.id_usuario = u.id_usuario)))
     JOIN public.detalle_bitacora d ON ((b.id_bitacora = d.id_bitacora)))
     JOIN public.columnas_auditadas c ON ((d.id_columna = c.id_columna)));


--
-- Name: tablas_auditadas_id_tabla_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.tablas_auditadas_id_tabla_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: tablas_auditadas_id_tabla_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.tablas_auditadas_id_tabla_seq OWNED BY public.tablas_auditadas.id_tabla;


--
-- Name: usuarios_auditados_id_usuario_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.usuarios_auditados_id_usuario_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: usuarios_auditados_id_usuario_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.usuarios_auditados_id_usuario_seq OWNED BY public.usuarios_auditados.id_usuario;


--
-- Name: bitacora_auditoria id_bitacora; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.bitacora_auditoria ALTER COLUMN id_bitacora SET DEFAULT nextval('public.bitacora_auditoria_id_bitacora_seq'::regclass);


--
-- Name: cliente_prueba id_cliente; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.cliente_prueba ALTER COLUMN id_cliente SET DEFAULT nextval('public.cliente_prueba_id_cliente_seq'::regclass);


--
-- Name: columnas_auditadas id_columna; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.columnas_auditadas ALTER COLUMN id_columna SET DEFAULT nextval('public.columnas_auditadas_id_columna_seq'::regclass);


--
-- Name: configuracion_auditoria id_config; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.configuracion_auditoria ALTER COLUMN id_config SET DEFAULT nextval('public.configuracion_auditoria_id_config_seq'::regclass);


--
-- Name: detalle_bitacora id_detalle; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.detalle_bitacora ALTER COLUMN id_detalle SET DEFAULT nextval('public.detalle_bitacora_id_detalle_seq'::regclass);


--
-- Name: estaciones_trabajo id_estacion; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.estaciones_trabajo ALTER COLUMN id_estacion SET DEFAULT nextval('public.estaciones_trabajo_id_estacion_seq'::regclass);


--
-- Name: eventos_auditoria id_evento; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.eventos_auditoria ALTER COLUMN id_evento SET DEFAULT nextval('public.eventos_auditoria_id_evento_seq'::regclass);


--
-- Name: productos_prueba id_producto; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.productos_prueba ALTER COLUMN id_producto SET DEFAULT nextval('public.productos_prueba_id_producto_seq'::regclass);


--
-- Name: tablas_auditadas id_tabla; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.tablas_auditadas ALTER COLUMN id_tabla SET DEFAULT nextval('public.tablas_auditadas_id_tabla_seq'::regclass);


--
-- Name: usuarios_auditados id_usuario; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.usuarios_auditados ALTER COLUMN id_usuario SET DEFAULT nextval('public.usuarios_auditados_id_usuario_seq'::regclass);


--
-- Name: bitacora_auditoria bitacora_auditoria_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.bitacora_auditoria
    ADD CONSTRAINT bitacora_auditoria_pkey PRIMARY KEY (id_bitacora);


--
-- Name: cliente_prueba cliente_prueba_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.cliente_prueba
    ADD CONSTRAINT cliente_prueba_pkey PRIMARY KEY (id_cliente);


--
-- Name: columnas_auditadas columnas_auditadas_id_tabla_nombre_columna_key; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.columnas_auditadas
    ADD CONSTRAINT columnas_auditadas_id_tabla_nombre_columna_key UNIQUE (id_tabla, nombre_columna);


--
-- Name: columnas_auditadas columnas_auditadas_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.columnas_auditadas
    ADD CONSTRAINT columnas_auditadas_pkey PRIMARY KEY (id_columna);


--
-- Name: configuracion_auditoria configuracion_auditoria_id_columna_id_evento_key; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.configuracion_auditoria
    ADD CONSTRAINT configuracion_auditoria_id_columna_id_evento_key UNIQUE (id_columna, id_evento);


--
-- Name: configuracion_auditoria configuracion_auditoria_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.configuracion_auditoria
    ADD CONSTRAINT configuracion_auditoria_pkey PRIMARY KEY (id_config);


--
-- Name: detalle_bitacora detalle_bitacora_id_bitacora_id_columna_key; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.detalle_bitacora
    ADD CONSTRAINT detalle_bitacora_id_bitacora_id_columna_key UNIQUE (id_bitacora, id_columna);


--
-- Name: detalle_bitacora detalle_bitacora_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.detalle_bitacora
    ADD CONSTRAINT detalle_bitacora_pkey PRIMARY KEY (id_detalle);


--
-- Name: estaciones_trabajo estaciones_trabajo_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.estaciones_trabajo
    ADD CONSTRAINT estaciones_trabajo_pkey PRIMARY KEY (id_estacion);


--
-- Name: eventos_auditoria eventos_auditoria_nombre_evento_key; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.eventos_auditoria
    ADD CONSTRAINT eventos_auditoria_nombre_evento_key UNIQUE (nombre_evento);


--
-- Name: eventos_auditoria eventos_auditoria_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.eventos_auditoria
    ADD CONSTRAINT eventos_auditoria_pkey PRIMARY KEY (id_evento);


--
-- Name: productos_prueba productos_prueba_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.productos_prueba
    ADD CONSTRAINT productos_prueba_pkey PRIMARY KEY (id_producto);


--
-- Name: tablas_auditadas tablas_auditadas_esquema_nombre_tabla_key; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.tablas_auditadas
    ADD CONSTRAINT tablas_auditadas_esquema_nombre_tabla_key UNIQUE (esquema, nombre_tabla);


--
-- Name: tablas_auditadas tablas_auditadas_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.tablas_auditadas
    ADD CONSTRAINT tablas_auditadas_pkey PRIMARY KEY (id_tabla);


--
-- Name: usuarios_auditados usuarios_auditados_nombre_usuario_key; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.usuarios_auditados
    ADD CONSTRAINT usuarios_auditados_nombre_usuario_key UNIQUE (nombre_usuario);


--
-- Name: usuarios_auditados usuarios_auditados_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.usuarios_auditados
    ADD CONSTRAINT usuarios_auditados_pkey PRIMARY KEY (id_usuario);


--
-- Name: cliente_prueba trg_autoaudit; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER trg_autoaudit AFTER INSERT OR DELETE OR UPDATE ON public.cliente_prueba FOR EACH ROW EXECUTE FUNCTION public.fn_autoaudit_generica();


--
-- Name: productos_prueba trg_autoaudit; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER trg_autoaudit AFTER INSERT OR DELETE OR UPDATE ON public.productos_prueba FOR EACH ROW EXECUTE FUNCTION public.fn_autoaudit_generica();


--
-- Name: bitacora_auditoria bitacora_auditoria_id_estacion_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.bitacora_auditoria
    ADD CONSTRAINT bitacora_auditoria_id_estacion_fkey FOREIGN KEY (id_estacion) REFERENCES public.estaciones_trabajo(id_estacion);


--
-- Name: bitacora_auditoria bitacora_auditoria_id_evento_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.bitacora_auditoria
    ADD CONSTRAINT bitacora_auditoria_id_evento_fkey FOREIGN KEY (id_evento) REFERENCES public.eventos_auditoria(id_evento);


--
-- Name: bitacora_auditoria bitacora_auditoria_id_tabla_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.bitacora_auditoria
    ADD CONSTRAINT bitacora_auditoria_id_tabla_fkey FOREIGN KEY (id_tabla) REFERENCES public.tablas_auditadas(id_tabla);


--
-- Name: bitacora_auditoria bitacora_auditoria_id_usuario_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.bitacora_auditoria
    ADD CONSTRAINT bitacora_auditoria_id_usuario_fkey FOREIGN KEY (id_usuario) REFERENCES public.usuarios_auditados(id_usuario);


--
-- Name: columnas_auditadas columnas_auditadas_id_tabla_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.columnas_auditadas
    ADD CONSTRAINT columnas_auditadas_id_tabla_fkey FOREIGN KEY (id_tabla) REFERENCES public.tablas_auditadas(id_tabla);


--
-- Name: configuracion_auditoria configuracion_auditoria_id_columna_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.configuracion_auditoria
    ADD CONSTRAINT configuracion_auditoria_id_columna_fkey FOREIGN KEY (id_columna) REFERENCES public.columnas_auditadas(id_columna);


--
-- Name: configuracion_auditoria configuracion_auditoria_id_evento_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.configuracion_auditoria
    ADD CONSTRAINT configuracion_auditoria_id_evento_fkey FOREIGN KEY (id_evento) REFERENCES public.eventos_auditoria(id_evento);


--
-- Name: detalle_bitacora detalle_bitacora_id_bitacora_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.detalle_bitacora
    ADD CONSTRAINT detalle_bitacora_id_bitacora_fkey FOREIGN KEY (id_bitacora) REFERENCES public.bitacora_auditoria(id_bitacora);


--
-- Name: detalle_bitacora detalle_bitacora_id_columna_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.detalle_bitacora
    ADD CONSTRAINT detalle_bitacora_id_columna_fkey FOREIGN KEY (id_columna) REFERENCES public.columnas_auditadas(id_columna);


--
-- PostgreSQL database dump complete
--

\unrestrict pLvDk6eGbr7sM932sj3ogdKTHSjvuyrS72TmL5I7QnTrAhhZXCxFqV8sB2H4Nfi

