# 01 - Base de datos

Este directorio incluye el esquema real exportado de PostgreSQL 18 (`estructura_actual.sql`) y las semillas de prueba (`semillas_y_prueba.sql`). Las semillas crean **cinco reglas** de auditoría en una base de prueba y comprueban el INSERT mediante una transacción que se revierte.

**Los registros persistentes originales no están incluidos:** el archivo binario `.dump` de Ubuntu y los CSV originales no formaban parte de los archivos disponibles en esta conversación. No se han inventado datos para sustituirlos. Las capturas en `03_Evidencias/` presentan los registros de ejemplo que se observaron en las pruebas.

Este SQL es material académico de demostración; no debe ejecutarse en producción ni en una base preexistente sin revisar previamente roles, propietarios y permisos.
