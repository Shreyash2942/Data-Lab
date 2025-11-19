# Spark Layer

PySpark examples use the local Spark install. You can also spin up the bundled services by running:

```bash
bash ~/app/start   # option 1 starts Spark; option 6 (or --start-core) launches Spark/Hadoop/Hive/Kafka
bash ~/app/stop    # stop everything when done
```

## Logging defaults

The helper scripts install a wrapper around `spark-submit` (`~/app/bin/spark-submit`) so you get quiet logs out of the box:

- `~/runtime/spark/conf/log4j2.properties` is auto-generated and pinned to `WARN` for both the root logger and `org.apache.spark`.
- The wrapper also passes `-Dlog4j.configurationFile=…` so every `spark-submit` (and PySpark job) picks up that config without extra flags.
- Extra Hadoop chatter such as `org.apache.hadoop.util.NativeCodeLoader` is forced to `ERROR`. Remove the `logger.hadoop.*` lines in that file if you need to see those warnings again.

If you prefer a different log level, edit `~/runtime/spark/conf/log4j2.properties` (or drop in your own) before running `bash ~/app/start --start-spark`.

## Resources
- Official docs: https://spark.apache.org/docs/latest/
