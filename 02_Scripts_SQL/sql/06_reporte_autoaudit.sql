-- AutoAudit: reporte consolidado de auditorias
-- Ejecutar SOLO en autoaudit_restauracion durante las pruebas.
-- Este script crea una vista; no borra ni modifica registros de auditoria.

CREATE OR REPLACE VIEW public.reporte_autoaudit AS
SELECT
    b.id_bitacora,
    t.nombre_tabla,
    e.nombre_evento,
    u.nombre_usuario,
    c.nombre_columna,
    d.valor_anterior,
    d.valor_nuevo,
    b.fecha_evento
FROM public.bitacora_auditoria AS b
JOIN public.tablas_auditadas AS t
    ON b.id_tabla = t.id_tabla
JOIN public.eventos_auditoria AS e
    ON b.id_evento = e.id_evento
LEFT JOIN public.usuarios_auditados AS u
    ON b.id_usuario = u.id_usuario
JOIN public.detalle_bitacora AS d
    ON b.id_bitacora = d.id_bitacora
JOIN public.columnas_auditadas AS c
    ON d.id_columna = c.id_columna;

SELECT * FROM public.reporte_autoaudit ORDER BY id_bitacora;
