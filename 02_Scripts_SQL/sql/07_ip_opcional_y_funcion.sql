-- APLICACIÓN OPCIONAL (NO AUTOMÁTICA) EN autoaudit_restauracion.
-- Agrega columna de IP y redefine la funcion de auditoria para registrarla.
-- La conexion Unix (sudo -u postgres psql) devuelve IP NULL; NO inventar 127.0.0.1.
-- IMPORTANTE: NO ejecutarlo en produccion sin una prueba de regresion.
-- Requiere previamente la funcion actual fn_autoaudit_generica() con su semántica confirmada.
ALTER TABLE public.bitacora_auditoria ADD COLUMN IF NOT EXISTS ip_origen inet;
-- Para evitar reemplazar incorrectamente toda la funcion existente, ejecutamos
-- una comprobacion segura y registramos instrucciones de implementacion. El
-- patch de fn_autoaudit_generica() se incluye en 07b_fn_con_ip.sql, que puede
-- ejecutarse separadamente despues de validar su definicion.
SELECT column_name,data_type FROM information_schema.columns
 WHERE table_schema='public' AND table_name='bitacora_auditoria' AND column_name='ip_origen';
