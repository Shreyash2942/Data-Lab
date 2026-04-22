-- Delta smoke test
SHOW SCHEMAS FROM delta;
SELECT 'delta' AS catalog_name, count(*) AS schema_count
FROM delta.information_schema.schemata;

