# Hadoop Layer

The monolithic container now includes a ready-to-run **single-node (pseudo-distributed) Hadoop stack**. Configuration lives in `dev/hadoop/conf/` and is baked into the image so you can start HDFS/YARN directly from inside the container.

## Quick usage
- Open a shell inside the running container (`docker compose exec data-lab bash`).
- Launch the helper: `bash /workspace/app/scripts/services_start.sh`.
- Choose option **3** to format (first run) and start NameNode, DataNode, YARN ResourceManager/NodeManager, and the MapReduce Job History server (along with Spark, Hive, and Kafka).
- When you're finished, run `/workspace/app/scripts/services_stop.sh` to stop the daemons (plus Spark/Hive/Kafka) cleanly.
- Hadoop data lives in `/workspace/hadoop/dfs`, so it persists on the host.

## Resources
- Official docs: https://hadoop.apache.org/docs/stable/
