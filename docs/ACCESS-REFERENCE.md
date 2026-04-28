# Access Reference

This page collects the URLs, endpoints, and built-in defaults that are useful once the platform is running.

## Web UIs and HTTP Services

- Airflow: `http://localhost:8080/`
- Spark Master UI: `http://localhost:9090/`
- Spark History: `http://localhost:18080/`
- Spark App UI: `http://localhost:4040/`
- HDFS NameNode: `http://localhost:9870/`
- YARN ResourceManager: `http://localhost:8088/`
- Kafka UI: `http://localhost:9002/`
- Schema Registry API: `http://localhost:8085/apis/registry/v3`
- Kafka Connect API: `http://localhost:8086/connectors`
- JupyterLab: `http://localhost:8888/lab?token=datalab`
- Great Expectations Data Docs: `http://localhost:8891/`
- Marquez UI: `http://localhost:3000/`
- Marquez API: `http://localhost:5000/api/v1/namespaces`
- Prometheus: `http://localhost:9095/`
- Grafana: `http://localhost:3001/`
- pgAdmin: `http://localhost:8181/`
- Trino: `http://localhost:8091/`
- Superset: `http://localhost:8090/`
- MinIO API: `http://localhost:9004/`
- MinIO Console: `http://localhost:9005/`

## Connection Endpoints

- Spark RPC: `spark://localhost:7077`
- Hive Metastore: `thrift://localhost:9083`
- HiveServer2 Thrift: `thrift://localhost:10000`
- PostgreSQL: `postgresql://localhost:5432`
- MongoDB: `mongodb://localhost:27017`
- Redis: `redis://localhost:6379`

## Built-In Defaults

- Airflow login: `datalab / admin` by default, or `${CONTAINER_NAME} / admin` when `CONTAINER_NAME` is set
- Jupyter token: `datalab`
- Superset login: `admin / admin`
- pgAdmin login: `admin@admin.com / admin`
- Grafana login: `admin / admin`
- MinIO login: `minio_admin / minioadmin`
- Trino default user: `trino`
- Trino default catalog and schema: `hive.default`
- Great Expectations result file: `/home/datalab/runtime/great_expectations/last_validation.json`
- Great Expectations demo dataset: `/home/datalab/runtime/great_expectations/demo_data/customer_events_quality.csv`
- Jupyter starter notebook: `/home/datalab/runtime/jupyter/notebooks/DataLab_Phase3_Quickstart.ipynb`
- OpenLineage namespace: `datalab` by default, or `CONTAINER_NAME` when set

## Built-In CDC Demo Names

- JSON mode: connector `datalab-postgres-cdc`, topic `datalab_cdc.public.customer_events`
- Registry mode: connector `datalab-postgres-cdc-registry`, topic `datalab_cdc-registry.public.customer_events`

## Built-In Lineage Demo Paths

- `/home/datalab/runtime/lineage/demo/bronze`
- `/home/datalab/runtime/lineage/demo/silver`

## Note On Port Mapping

These values describe the default local ports. If you run copied containers or remap ports, use `ui_services` or `datalab_app` to get the correct host-side URLs.
