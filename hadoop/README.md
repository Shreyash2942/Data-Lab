# Hadoop Layer

The monolithic container now includes a ready-to-run **single-node (pseudo-distributed) Hadoop stack**. Configuration lives in `dev/hadoop/conf/` and is baked into the image so you can start HDFS/YARN directly from inside the container.

## Quick usage
- Open a shell inside the running container (`docker compose exec data-lab bash`).
- Launch the helper: `bash ~/app/start`.
- Choose option **2** to format (first run) and start NameNode, DataNode, YARN ResourceManager/NodeManager, and the MapReduce Job History server. Use option 6 (or `~/app/start --start-core`) if you want the full Spark/Hadoop/Hive/Kafka stack.
- When you're finished, run `~/app/stop` to stop the daemons (and any other services you started) cleanly.
- Hadoop data lives in `~/runtime/hadoop/dfs`, so it persists on the host.

## HDFS smoke test

Need to confirm HDFS is reachable? After starting Hadoop, run:

```bash
bash ~/hadoop/scripts/hdfs_check.sh
```

The script uploads `~/hadoop/sample_data/hello_hdfs.txt` into `/data-lab/demo/hello_hdfs.txt` inside HDFS, lists the directory, and prints the file back so you can validate NameNode/DataNode access immediately.

## Resources
- Official docs: https://hadoop.apache.org/docs/stable/
