-- AutoAudit: primera funcion de registro de modificaciones del telefono.
-- Requiere las tablas y la configuracion de prueba ya creadas.
-- El trigger trg_prueba_auditoria existente ejecuta esta funcion.

CREATE OR REPLACE FUNCTION public.fn_prueba_auditoria()
RETURNS TRIGGER AS $$
DECLARE
    v_bitacora BIGINT;
    v_id_tabla BIGINT;
    v_id_columna BIGINT;
    v_id_evento BIGINT;
    v_id_usuario BIGINT;
BEGIN
    -- Solo registra un cambio efectivo del telefono.
    IF OLD.telefono IS DISTINCT FROM NEW.telefono THEN
        SELECT ta.id_tabla, ca.id_columna, ea.id_evento
          INTO v_id_tabla, v_id_columna, v_id_evento
          FROM public.tablas_auditadas AS ta
          JOIN public.columnas_auditadas AS ca ON ca.id_tabla = ta.id_tabla
          JOIN public.configuracion_auditoria AS cfg ON cfg.id_columna = ca.id_columna
          JOIN public.eventos_auditoria AS ea ON ea.id_evento = cfg.id_evento
         WHERE ta.esquema = TG_TABLE_SCHEMA
           AND ta.nombre_tabla = TG_TABLE_NAME
           AND ca.nombre_columna = 'telefono'
           AND ea.nombre_evento = TG_OP
           AND ta.activa IS TRUE
           AND ca.activa IS TRUE
           AND cfg.activa IS TRUE
         LIMIT 1;

        IF FOUND THEN
            SELECT id_usuario INTO v_id_usuario
              FROM public.usuarios_auditados
             WHERE nombre_usuario = session_user
               AND activo IS TRUE
             LIMIT 1;

            INSERT INTO public.bitacora_auditoria
                (id_tabla, id_evento, id_usuario, registro_id)
            VALUES
                (v_id_tabla, v_id_evento, v_id_usuario, NEW.id_cliente::TEXT)
            RETURNING id_bitacora INTO v_bitacora;

            INSERT INTO public.detalle_bitacora
                (id_bitacora, id_columna, valor_anterior, valor_nuevo)
            VALUES
                (v_bitacora, v_id_columna, OLD.telefono, NEW.telefono);
        END IF;
    END IF;

    RETURN NEW;
END;
$$ LANGUAGE plpgsql;
