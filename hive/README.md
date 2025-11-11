# Hive Layer

Hive now ships with a configured embedded Derby metastore and warehouse path (`/workspace/hive/warehouse`). Start the background services from inside the container with:

```bash
bash /workspace/app/scripts/services_start.sh   # choose option 3 to start the stack (Spark/Hadoop/Kafka included)
bash /workspace/app/scripts/services_stop.sh    # stop Spark/Hadoop/Hive/Kafka when finished
```

This spins up both the Hive metastore service and HiveServer2 so you can connect through JDBC (`jdbc:hive2://localhost:10000`). The CLI is still available for ad-hoc queries:

```bash
hive -e 'SHOW DATABASES;'
```

## Resources
- Official docs: https://cwiki.apache.org/confluence/display/Hive/Home
