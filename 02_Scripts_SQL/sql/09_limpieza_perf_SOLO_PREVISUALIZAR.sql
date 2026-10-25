-- NO ELIMINA NADA. Los 1000 productos insertados fuera de transaccion se mantienen.
SELECT COUNT(*) AS productos_de_prueba
FROM public.productos_prueba WHERE nombre LIKE 'AA-PERF-%';
-- Para limpiarlos mas adelante, realizar respaldo y revisar referencias, y
-- ejecutar conscientemente un DELETE limitado dentro de una transaccion.
