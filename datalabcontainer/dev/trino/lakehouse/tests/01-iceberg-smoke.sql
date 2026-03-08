-- Iceberg smoke test
SHOW SCHEMAS FROM iceberg;
SELECT 'iceberg' AS catalog_name, count(*) AS schema_count
FROM iceberg.information_schema.schemata;

