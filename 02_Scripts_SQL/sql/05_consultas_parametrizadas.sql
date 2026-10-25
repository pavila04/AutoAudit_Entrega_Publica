-- Consultas de ejemplo para psql; no alteran datos. Se preparan por sesión.
PREPARE aa_por_usuario(text) AS
 SELECT * FROM public.reporte_autoaudit WHERE nombre_usuario=$1 ORDER BY fecha_evento;
PREPARE aa_por_columna(text,text) AS
 SELECT * FROM public.reporte_autoaudit WHERE nombre_tabla=$1 AND nombre_columna=$2 ORDER BY fecha_evento;
PREPARE aa_por_fechas(timestamptz,timestamptz) AS
 SELECT * FROM public.reporte_autoaudit WHERE fecha_evento >=$1 AND fecha_evento<$2 ORDER BY fecha_evento;
EXECUTE aa_por_usuario('autoaudit_admin');
EXECUTE aa_por_columna('productos_prueba','precio');
EXECUTE aa_por_fechas('2026-10-24 00:00-06','2026-10-25 00:00-06');
