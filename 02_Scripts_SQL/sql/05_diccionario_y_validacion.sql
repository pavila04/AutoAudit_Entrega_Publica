-- AutoAudit: extracción de diccionario y validación de requisitos del profesor.
-- Ejecutar con psql -f sobre autoaudit. Solo consultas, no altera datos.
\pset pager off
\echo === COLUMNAS DEL ESQUEMA PUBLIC (ordenadas) ===
SELECT table_name, ordinal_position, column_name, data_type,
       is_nullable, column_default
FROM information_schema.columns
WHERE table_schema='public'
ORDER BY table_name, ordinal_position;

\echo === CLAVES PRIMARIAS Y FORANEAS ===
SELECT tc.table_name, tc.constraint_type, tc.constraint_name,
       kcu.column_name, ccu.table_name AS referenced_table,
       ccu.column_name AS referenced_column
FROM information_schema.table_constraints tc
JOIN information_schema.key_column_usage kcu
  ON tc.constraint_name=kcu.constraint_name
 AND tc.constraint_schema=kcu.constraint_schema
LEFT JOIN information_schema.constraint_column_usage ccu
  ON tc.constraint_name=ccu.constraint_name
 AND tc.constraint_schema=ccu.constraint_schema
WHERE tc.table_schema='public'
  AND tc.constraint_type IN ('PRIMARY KEY','FOREIGN KEY')
ORDER BY tc.table_name,tc.constraint_type,kcu.ordinal_position;

\echo === TRIGGERS DE AUDITORIA ===
SELECT ns.nspname AS esquema, c.relname AS tabla, t.tgname AS trigger,
       pg_get_triggerdef(t.oid) AS definicion
FROM pg_catalog.pg_trigger t
JOIN pg_catalog.pg_class c ON c.oid=t.tgrelid
JOIN pg_catalog.pg_namespace ns ON ns.oid=c.relnamespace
WHERE NOT t.tgisinternal AND t.tgname='trg_autoaudit'
ORDER BY ns.nspname,c.relname;

\echo === ESTADO DE CONFIGURACION ===
SELECT t.esquema, t.nombre_tabla, c.nombre_columna, e.nombre_evento,
       t.activa AS tabla_activa, c.activa AS columna_activa,
       cfg.activa AS regla_activa
FROM public.configuracion_auditoria cfg
JOIN public.columnas_auditadas c ON c.id_columna=cfg.id_columna
JOIN public.tablas_auditadas t ON t.id_tabla=c.id_tabla
JOIN public.eventos_auditoria e ON e.id_evento=cfg.id_evento
ORDER BY t.esquema,t.nombre_tabla,c.nombre_columna,e.nombre_evento;
