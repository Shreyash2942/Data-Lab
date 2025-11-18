# Hive Layer

Hive now ships with a configured embedded Derby metastore and warehouse path (`~/runtime/hive/warehouse`). Prepare the CLI from inside the container with:

```bash
bash ~/app/start   # choose option 3 to prep the metastore
bash ~/app/stop    # stop Spark/Hadoop/Hive/Kafka when finished
```

Use option 6 (or `~/app/start --start-core`) if you want the entire Spark/Hadoop/Hive/Kafka stack in one go.

That command ensures Hadoop is running, creates any missing metastore tables, and drops you back into the shell so you can run Hive directly. From any directory in the container you can now type:

- `hivelegacy` – wraps `~/app/scripts/hive/legacy_cli.sh`, auto-connects to HS2, and shows prompts like `hive (default)>`.
- `hivecli` – wraps `~/app/scripts/hive/cli.sh`, launching Beeline against the same endpoint.

Both obey the `HIVE_CLI_HOST/PORT/HTTP_PATH/AUTH/USER/PASS` environment variables, so you can point them at any HS2 you start manually. Prefer Spark? `spark-sql -e 'SHOW DATABASES;'` works too.

### Need HiveServer2?

Only start HS2 when you need a JDBC/ODBC endpoint (e.g. for Airflow’s Hive hook). Use the helper script (run as root inside the container):

```bash
# from the host (datalab user or root)
docker compose exec -u datalab data-lab bash
bash ~/app/scripts/hive/hs2.sh start
```

That launches HS2 over HTTP (`localhost:10001/cliservice`), waits for the port, and runs a verification query via the Beeline helper. Stop it with `bash ~/app/scripts/hive/hs2.sh stop`. Connect via:

```
beeline -u 'jdbc:hive2://localhost:10001/default;transportMode=http;httpPath=cliservice;auth=noSasl' -n datalab -p ''
```

## Demo databases

After Hive is running, create a few ready-made schemas/tables with:

```bash
bash ~/hive/bootstrap_demo.sh
```

The helper uses the Hive CLI (so you'll see the `hive (<current-db>)>` prompt) to create the `sales_demo`, `analytics_demo`, and `staging_demo` databases from `~/hive/init_demo_databases.sql`, loads sample rows, and shows the resulting tables so you can verify HiveServer2 quickly.

## Resources
- Official docs: https://cwiki.apache.org/confluence/display/Hive/Home
