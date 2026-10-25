\pset pager off
\echo === TABLAS DE LA BASE RESTAURADA ===
SELECT schemaname,tablename,tableowner FROM pg_catalog.pg_tables WHERE schemaname='public' ORDER BY tablename;
\echo === CONTEO DE AUDITORIAS ===
SELECT COUNT(*) AS bitacoras FROM public.bitacora_auditoria;
SELECT COUNT(*) AS detalles FROM public.detalle_bitacora;
\echo === RESUMEN POR EVENTO ===
SELECT e.nombre_evento, COUNT(*) AS total FROM public.bitacora_auditoria b
JOIN public.eventos_auditoria e ON b.id_evento=e.id_evento GROUP BY e.nombre_evento ORDER BY 1;
\echo === REGLAS HABILITADAS ===
SELECT t.esquema,t.nombre_tabla,c.nombre_columna,e.nombre_evento,cfg.activa
FROM public.configuracion_auditoria cfg JOIN public.columnas_auditadas c ON c.id_columna=cfg.id_columna
JOIN public.tablas_auditadas t ON t.id_tabla=c.id_tabla
JOIN public.eventos_auditoria e ON e.id_evento=cfg.id_evento
ORDER BY t.nombre_tabla,c.nombre_columna,e.nombre_evento;
\echo === FUNCIONES Y TRIGGERS ===
SELECT p.proname FROM pg_catalog.pg_proc p JOIN pg_catalog.pg_namespace n ON n.oid=p.pronamespace
WHERE n.nspname='public' AND p.proname LIKE 'fn_%autoaudit%';
SELECT c.relname,t.tgname FROM pg_catalog.pg_trigger t JOIN pg_catalog.pg_class c ON c.oid=t.tgrelid
WHERE NOT t.tgisinternal AND t.tgname='trg_autoaudit' ORDER BY 1;
