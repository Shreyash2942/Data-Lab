-- Run in Trino SQL after Spark writes Delta files
CALL delta.system.unregister_table(
  schema_name => 'demo_delta',
  table_name => 'table_delta'
);

CALL delta.system.register_table(
  schema_name => 'demo_delta',
  table_name => 'table_delta',
  table_location => 'hdfs://localhost:9000/datalake/delta/demo_delta/table_delta'
);
