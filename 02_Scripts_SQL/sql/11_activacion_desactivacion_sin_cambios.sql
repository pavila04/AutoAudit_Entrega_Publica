-- Demostración de activación/desactivación SIN dejar cambios permanentes.
-- EN autoaudit_restauracion, después de respaldar.
BEGIN;
SELECT t.nombre_tabla,c.nombre_columna,e.nombre_evento,cfg.activa
FROM public.configuracion_auditoria cfg
JOIN public.columnas_auditadas c ON cfg.id_columna=c.id_columna
JOIN public.tablas_auditadas t ON t.id_tabla=c.id_tabla
JOIN public.eventos_auditoria e ON e.id_evento=cfg.id_evento
WHERE t.nombre_tabla='productos_prueba' AND c.nombre_columna='precio';
UPDATE public.configuracion_auditoria AS cfg SET activa=FALSE
FROM public.columnas_auditadas AS c
JOIN public.tablas_auditadas AS t ON t.id_tabla=c.id_tabla
JOIN public.eventos_auditoria AS e ON e.nombre_evento='UPDATE'
WHERE cfg.id_columna=c.id_columna AND cfg.id_evento=e.id_evento
AND t.nombre_tabla='productos_prueba' AND c.nombre_columna='precio';
SELECT t.nombre_tabla,c.nombre_columna,e.nombre_evento,cfg.activa
FROM public.configuracion_auditoria cfg
JOIN public.columnas_auditadas c ON cfg.id_columna=c.id_columna
JOIN public.tablas_auditadas t ON t.id_tabla=c.id_tabla
JOIN public.eventos_auditoria e ON e.id_evento=cfg.id_evento
WHERE t.nombre_tabla='productos_prueba' AND c.nombre_columna='precio';
ROLLBACK;
-- No se ha desactivado permanentemente la auditoría.
