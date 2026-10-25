-- Usar SOLO en autoaudit_restauracion. Cambios transaccionales revertidos.
-- Ejecutar en sesión local de postgres. Se usa session auth para identificar usuario.
SET SESSION AUTHORIZATION autoaudit_admin;
BEGIN;
UPDATE public.productos_prueba SET precio=precio+0.01 WHERE id_producto=1;
SELECT b.id_bitacora, b.fecha_evento, d.valor_anterior,d.valor_nuevo
FROM public.bitacora_auditoria b JOIN public.detalle_bitacora d ON b.id_bitacora=d.id_bitacora
ORDER BY b.id_bitacora DESC LIMIT 1;
ROLLBACK;
RESET SESSION AUTHORIZATION;
