# Data Lab Future Roadmap: Data Engineering Expansion

This document captures the next recommended data engineering additions that can extend Data Lab without changing the current required topology.

Status:

1. Phase 1 foundation is implemented in the container: Schema Registry + Kafka Connect.
2. Phase 2 CDC ingestion is implemented for PostgreSQL -> Debezium -> Kafka.
3. Phase 3 quality/dev workflow is implemented in the container: Great Expectations + JupyterLab.
4. Phase 4 lineage/observability is implemented in the container: OpenLineage + Marquez + Prometheus + Grafana.
5. Validated demo modes now include:
   - JSON messages with `datalab-postgres-cdc` -> `datalab_cdc.public.customer_events`
   - Schema Registry-backed messages with `datalab-postgres-cdc-registry` -> `datalab_cdc-registry.public.customer_events`
6. Validated observability flows now include:
   - `datalab_app --start-observability-stack`
   - `datalab_app --run-lineage-demo`
   - host-mapped Marquez, Prometheus, and Grafana URLs through `ui_services`
7. Optional MongoDB CDC remains a later extension inside the ingestion phase.

## Goals

1. Fill the biggest platform gaps around ingestion, governance, quality, lineage, and observability.
2. Reuse the current Spark, Airflow, Kafka, Hive, Trino, dbt, Superset, PostgreSQL, Redis, MinIO, and lakehouse foundation.
3. Keep every future service compatible with the current single-container modular design.
4. Preserve dynamic host port support for copied containers.

## Required Topology Contract

These recommendations assume the current Data Lab topology stays in place.

1. Single container remains the default runtime model.
2. New services should be optional and started through `datalab_app`.
3. Each service should follow the same module pattern.
Service module path: `datalabcontainer/app/tech/<service>/manage.sh`
Build/config path: `datalabcontainer/dev/<service>/` or `datalabcontainer/dev/tech/<service>/`
4. Runtime state should stay under `~/runtime/<service>`.
5. New service UIs and endpoints should be surfaced through `ui_services`.

## Dynamic Port Support Requirements

Every future addition should work when a copied container receives remapped host ports.

1. Keep a stable internal container port per service.
2. Treat the outside host port as dynamic.
3. Resolve outside-host URLs from `DATALAB_HOST_PORT_MAP`.
4. Print both inside-container and outside-host endpoints in `ui_services` when users interact with the service directly.
5. Avoid hardcoding host URLs inside docs, helper scripts, or startup output.

## Recommended Additions By Priority

## Phase 1: Foundation

Current status:

1. Schema Registry service is implemented in the container.
2. Kafka Connect service is implemented in the container.
3. The current topology and dynamic-port model are already wired into both services.

Scope:

1. Add a schema registry service.
2. Add Kafka Connect.

Why this phase comes first:

1. Kafka is already present in the stack.
2. CDC and connector-based ingestion are major missing pieces in the current platform.
3. Schema control improves reliability before pipelines become larger.

Recommended fit for the current topology:

1. Prefer a lightweight schema registry option such as Apicurio Registry.
2. Treat Kafka Connect as an optional service, not always-on by default.
3. Keep connector configs and example pipelines under `stacks/kafka/` or a future `stacks/ingestion/`.

Success criteria:

1. A connector can move data into Kafka without manual ad hoc scripts.
2. Schemas are versioned and visible through a registry UI or API.
3. Copied containers still show correct UI/API host endpoints through `ui_services`.

## Phase 2: CDC and Ingestion Workflows

Current status:

1. PostgreSQL logical replication settings are applied automatically.
2. A dedicated CDC user is bootstrapped for Debezium.
3. A validated PostgreSQL CDC demo is available through `datalab_app`.
4. JSON mode and Schema Registry-backed mode are both validated.

Scope:

1. Add Debezium.
2. Add PostgreSQL CDC into Kafka.
3. Keep MongoDB CDC as an optional later addition inside this phase.
4. Provide sample source connector configs.
5. Provide a topic verification flow.
6. Use Schema Registry integration where useful.

Why this phase comes next:

1. Phase 1 gave the platform services, but not a complete ingestion path.
2. CDC is one of the highest-value missing data engineering workflows in the current stack.
3. PostgreSQL is already embedded, so the demo stays aligned with the single-container topology.

Recommended fit for the current topology:

1. Keep CDC as an optional demo/service flow, not part of every default startup path.
2. Use stable internal ports and host-port mapping through `ui_services`.
3. Keep sample connector configs under `stacks/kafka/connectors/`.
4. Use separate connector/topic defaults for JSON mode and registry mode so demos stay rerunnable.

Validated commands:

1. `datalab_app --setup-postgres-cdc`
2. `datalab_app --verify-postgres-cdc`
3. `datalab_app --reset-postgres-cdc`
4. `CDC_SOURCE_MODE=registry datalab_app --setup-postgres-cdc`
5. `CDC_SOURCE_MODE=registry datalab_app --verify-postgres-cdc`

Success criteria:

1. PostgreSQL changes are captured into Kafka through Debezium.
2. Kafka Connect and Schema Registry work with the existing dynamic-port topology.
3. Users can verify connector health and sample messages directly from `datalab_app`.
4. Registry-backed mode produces schema artifacts in Apicurio Registry.

## Phase 3: Data Quality and Interactive Development

Current status:

1. Great Expectations demo validation is implemented.
2. Great Expectations Data Docs can be started through `datalab_app`.
3. JupyterLab is implemented with a starter notebook and dynamic host-port support.
4. `ui_services` exposes both host-mapped URLs for copied containers.

Scope:

1. Add Great Expectations for validation and expectation suites.
2. Add JupyterLab for ad hoc notebook work and PySpark exploration.

Why this phase comes next:

1. The current stack already has orchestration and compute.
2. Data quality and notebook workflows make the platform more usable day to day.
3. These additions are valuable without forcing a topology change.

Recommended fit for the current topology:

1. Keep Great Expectations mostly CLI and batch-oriented through Airflow/Spark jobs.
2. Treat JupyterLab as optional because it adds another interactive UI and memory pressure.
3. Write validation outputs to tables or files that Superset can read later.

Success criteria:

1. At least one Airflow DAG can run a validation checkpoint before downstream tasks.
2. Notebook access works with the same inside/outside endpoint model as the rest of the stack.
3. Validation results are visible outside the raw logs.

Validated commands:

1. `datalab_app --start-quality-stack`
2. `datalab_app --run-great-expectations-demo`
3. `datalab_app --start-jupyter`
4. `datalab_app --start-great-expectations`

## Phase 4: Lineage and Observability

Current status:

1. Marquez API and UI are implemented as optional services.
2. OpenLineage Spark emission is implemented through the shared `spark-submit` wrapper.
3. Prometheus and Grafana are implemented as optional monitoring services.
4. Dynamic host-port mapping is wired into `datalab_app`, `ui_services`, compose files, and copy-container helpers.

Scope:

1. Add OpenLineage-compatible event emission.
2. Add Marquez as a lightweight lineage backend and UI.
3. Add Prometheus and Grafana for service metrics and dashboards.

Why this phase is recommended over a heavier catalog first:

1. It fits the current monolithic topology better than a large metadata platform.
2. It gives immediate value for pipeline visibility and service health.
3. It avoids pushing the container into a much heavier governance footprint too early.

Recommended fit for the current topology:

1. Prefer OpenLineage + Marquez before introducing a heavier catalog such as OpenMetadata or DataHub.
2. Treat Prometheus and Grafana as optional monitoring modules.
3. Keep dashboards and scrape targets documented through the same helper/UI path.

Success criteria:

1. Airflow or Spark jobs emit lineage that can be inspected.
2. Core service health is visible in Grafana dashboards.
3. Dynamic port mapping works cleanly for Marquez and Grafana UIs.

Validated commands:

1. `datalab_app --start-observability-stack`
2. `datalab_app --run-lineage-demo`
3. `datalab_app --start-lineage`
4. `datalab_app --start-prometheus`
5. `datalab_app --start-grafana`

## Optional Future: Lakehouse Workflow Maturity

Scope:

1. Add lakeFS for data versioning and branch-style workflows.
2. Add example branch/test/promote flows for object-storage-based datasets.

Why this is optional:

1. It is powerful, but not required for the core learning and demo goals.
2. It adds more storage and workflow complexity.
3. It is most useful once ingestion, quality, and lineage are already in place.

Success criteria:

1. A branch-style data workflow can be demonstrated using MinIO-backed data.
2. The feature remains optional and does not bloat the default start path.

## Better Deferred Until A Future Multi-Container Profile

These are valid tools, but they are heavier for the current required topology.

1. OpenMetadata
2. DataHub
3. Flink as a dedicated stream-processing layer

Reason for deferral:

1. They are better fits when service isolation and independent scaling matter more.
2. They add more operational complexity than the current single-container goal needs.

## Proposed Future Module Layout

1. `datalabcontainer/app/tech/schema_registry/manage.sh`
2. `datalabcontainer/app/tech/kafka_connect/manage.sh`
3. `datalabcontainer/app/tech/great_expectations/manage.sh`
4. `datalabcontainer/app/tech/jupyter/manage.sh`
5. `datalabcontainer/app/tech/lineage/manage.sh`
6. `datalabcontainer/app/tech/monitoring/manage.sh`
7. `datalabcontainer/app/tech/lakefs/manage.sh`
8. `datalabcontainer/app/ui_services` entries for all new UIs and APIs
9. `datalabcontainer/app/start` menu integration for optional start paths

## Resource Profile For This Topology

Practical guidance if these data engineering expansion services are added later while staying single-container:

1. Minimum practical target: 8 vCPU, 24 GB RAM, 100 GB SSD
2. Better target for schema registry + Kafka Connect + Jupyter + monitoring together: 12 vCPU, 32 GB RAM, 150 GB SSD
3. Heavier optional profile with lineage and additional UIs: 12 to 16 vCPU, 32 to 48 GB RAM, 150 to 200 GB SSD

## Implementation Order

1. Schema registry
2. Kafka Connect
3. Debezium PostgreSQL CDC
4. Great Expectations
5. JupyterLab
6. OpenLineage + Marquez
7. Prometheus + Grafana
8. lakeFS

## References

1. Apicurio Registry docs: https://www.apicur.io/registry/docs/apicurio-registry/3.1.x/index.html
2. Apache Kafka Connect docs: https://kafka.apache.org/documentation/#connect
3. Debezium docs: https://debezium.io/documentation/reference/stable/
4. Great Expectations docs: https://docs.greatexpectations.io/
5. Project Jupyter: https://jupyter.org/
6. OpenLineage: https://openlineage.io/
7. Prometheus docs: https://prometheus.io/docs/prometheus/latest/getting_started/
8. Grafana docs: https://grafana.com/docs/
9. lakeFS docs: https://docs.lakefs.io/
