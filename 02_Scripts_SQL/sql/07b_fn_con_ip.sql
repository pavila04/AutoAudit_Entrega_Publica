-- EXPERIMENTAL / OPT-IN. EJECUTAR SOLO EN autoaudit_restauracion.
-- REQUIERE 07_ip_opcional_y_funcion.sql previamente.
-- La función existente se reemplaza: mantiene su firma y no elimina triggers.
-- El dueño debe ser autoaudit_admin para evitar superuser SECURITY DEFINER.
-- Confirmar el propietario con 02_diagnostico_seguridad.sql.
-- SECURITY DEFINER reduce errores al insertar bitácoras desde roles limitados,
-- pero no elimina la capacidad de un PROPIETARIO de modificar sus tablas.
-- Este archivo se basa en 03_autoaudit_generica.sql (versión disponible).
-- AutoAudit / Etapa 3: funcion de auditoria reutilizable
-- Compatible con PostgreSQL 18.
-- Requiere las ocho tablas de AutoAudit creadas previamente en public.
-- Conserva los registros existentes en la bitacora.
-- No modifica los datos de cliente_prueba.
-- IMPORTANTE: El trigger se instala SOLO en public.cliente_prueba para probarlo.
-- Se ejecuta con las credenciales del usuario que modifica la tabla.

CREATE OR REPLACE FUNCTION public.fn_autoaudit_generica()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog, pg_temp
AS $autoaudit$
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
$autoaudit$;


SELECT p.proname,pg_get_userbyid(p.proowner) AS propietario, p.prosecdef
FROM pg_catalog.pg_proc p WHERE p.oid='public.fn_autoaudit_generica()'::regprocedure;
