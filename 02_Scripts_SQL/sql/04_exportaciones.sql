-- psql debe ejecutarse como postgres del sistema; rutas /tmp propiedad del usuario postgres.
\pset pager off
\echo === EXPORTANDO REPORTE CONSOLIDADO ===
\copy (SELECT * FROM public.reporte_autoaudit ORDER BY id_bitacora) TO '/tmp/autoaudit_consolidado_final.csv' WITH (FORMAT csv, HEADER true)
\echo === EXPORTANDO DICCIONARIO DE DATOS ===
\copy (SELECT table_name,ordinal_position,column_name,data_type,is_nullable,column_default FROM information_schema.columns WHERE table_schema='public' ORDER BY table_name,ordinal_position) TO '/tmp/autoaudit_diccionario_final.csv' WITH (FORMAT csv, HEADER true)
\echo === EXPORTANDO RESTRICCIONES Y RELACIONES ===
\copy (SELECT con.conname AS restriccion,con.contype AS tipo,con.conrelid::regclass::text AS tabla,con.confrelid::regclass::text AS referencia,pg_get_constraintdef(con.oid) AS definicion FROM pg_catalog.pg_constraint con WHERE con.connamespace='public'::regnamespace ORDER BY con.conrelid::regclass::text,con.conname) TO '/tmp/autoaudit_relaciones_final.csv' WITH (FORMAT csv, HEADER true)
\echo === EXPORTANDO CONFIGURACION ===
\copy (SELECT t.esquema,t.nombre_tabla,c.nombre_columna,e.nombre_evento,t.activa AS tabla_activa,c.activa AS columna_activa,cfg.activa AS regla_activa FROM public.configuracion_auditoria cfg JOIN public.columnas_auditadas c ON cfg.id_columna=c.id_columna JOIN public.tablas_auditadas t ON t.id_tabla=c.id_tabla JOIN public.eventos_auditoria e ON cfg.id_evento=e.id_evento ORDER BY t.nombre_tabla,c.nombre_columna,e.nombre_evento) TO '/tmp/autoaudit_configuracion_final.csv' WITH (FORMAT csv, HEADER true)
