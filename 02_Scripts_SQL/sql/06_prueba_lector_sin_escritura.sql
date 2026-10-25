-- Validar acceso efectivo no destructivo usando SET LOCAL ROLE y ROLLBACK.
BEGIN;
SET LOCAL ROLE autoaudit_lector;
SELECT current_user AS rol_en_prueba;
SELECT COUNT(*) AS bitacoras_visibles FROM public.bitacora_auditoria;
SELECT COUNT(*) AS detalles_visibles FROM public.detalle_bitacora;
SELECT has_table_privilege(current_user,'public.bitacora_auditoria','INSERT') AS puede_insertar,
       has_table_privilege(current_user,'public.bitacora_auditoria','UPDATE') AS puede_modificar,
       has_table_privilege(current_user,'public.bitacora_auditoria','DELETE') AS puede_borrar;
ROLLBACK;
