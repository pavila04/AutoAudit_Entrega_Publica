-- AutoAudit - Etapa 4. Generación dinámica de triggers por tabla configurada.
-- PostgreSQL 18 / PLpgSQL.
-- REQUISITOS: public.fn_autoaudit_generica() existente y tablas de configuración.
-- No modifica datos de negocio ni borra registros de bitácora.
-- RECOMENDADO: probar primero en autoaudit_restauracion; luego en autoaudit.
-- Primera ejecución: crea la función. Después el administrador deberá llamar:
--   SELECT * FROM public.fn_sincronizar_triggers_autoaudit();
-- Esta versión automatiza la instalación a demanda; aún NO se ejecuta sola
-- al modificar las tablas de configuración.

CREATE OR REPLACE FUNCTION public.fn_sincronizar_triggers_autoaudit()
RETURNS TABLE (esquema text, tabla text, resultado text)
LANGUAGE plpgsql
SECURITY INVOKER
AS $autoaudit$
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
$autoaudit$;

-- Comprobar que existe la función ANTES de activar manualmente el despliegue.
SELECT p.proname AS funcion, n.nspname AS esquema
FROM pg_catalog.pg_proc p
JOIN pg_catalog.pg_namespace n ON n.oid=p.pronamespace
WHERE n.nspname='public' AND p.proname='fn_sincronizar_triggers_autoaudit';
