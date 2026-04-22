-- Hudi smoke test
SHOW SCHEMAS FROM hudi;
SELECT 'hudi' AS catalog_name, count(*) AS schema_count
FROM hudi.information_schema.schemata;

