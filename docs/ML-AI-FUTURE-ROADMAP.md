# Data Lab Future Roadmap: Machine Learning and AI

This document captures the future implementation plan to extend Data Lab from data engineering into machine learning and AI workloads, without changing the current core topology.

Status: planning only (no implementation in this phase).

## Goals

1. Reuse existing platform building blocks (Airflow, Spark, PostgreSQL, MinIO, Redis, Superset).
2. Add a practical MLOps flow: experiment tracking, model registry, batch/real-time inference.
3. Keep each new capability modular so it can be enabled/disabled per container profile.
4. Preserve current data engineering workflows and scripts.
5. Keep future AI/ML work compatible with copied containers and dynamic host port mapping.

## Guiding Principles

1. No breaking changes to current ETL and lakehouse stack.
2. New services are optional and start through tech modules, same as existing pattern.
3. Runtime state stays under `~/runtime/<service>`.
4. Keep SQL and Spark flows first-class; ML/AI augments, not replaces, current stack.
5. Preserve the current required topology: one container, modular service scripts, env-driven runtime wiring.

## Required Topology Contract

Future AI/ML services should fit the current Data Lab design rather than introduce a second orchestration model.

1. Stay inside the current single-container topology by default.
2. Follow the same service module pattern already used by the rest of the stack.
Service module path: `datalabcontainer/app/tech/<service>/manage.sh`
Build/config path: `datalabcontainer/dev/<service>/` or `datalabcontainer/dev/tech/<service>/`
3. Integrate into `datalab_app` and `ui_services` instead of adding a separate top-level launcher.
4. Keep service state under `~/runtime/<service>`.
5. Treat GPU-heavy or LLM-heavy features as optional profiles, not always-on defaults.

## Dynamic Port Support Requirements

Future AI/ML services should behave the same way current database and UI services behave in copied containers.

1. Each service should listen on a stable internal container port.
2. Host ports should be treated as dynamic and resolved through `DATALAB_HOST_PORT_MAP`.
3. `ui_services` should print both inside-container and outside-host endpoints for any UI or API that users access directly.
4. Docs should avoid assuming `localhost:<fixed-port>` on the host when copied containers may remap ports.
5. If a future service has both API and UI endpoints, both should participate in the same host-mapping pattern.

## Phase Plan

## Phase 1: MLOps Foundation (Recommended First)

Scope:

1. Add MLflow tracking server.
2. Use PostgreSQL as MLflow backend store.
3. Use MinIO as MLflow artifact store.
4. Add one Airflow DAG for train -> evaluate -> register flow.
5. Add one inference service (batch or API) for registered models.
6. Surface the resolved host URL in `ui_services` for copied-container support.

Success criteria:

1. Experiments and metrics visible in MLflow UI.
2. Model versions promoted through stages (`Staging`, `Production`).
3. Airflow can run end-to-end training + registration pipeline.
4. MLflow remains reachable through host-mapped ports when the container is copied.

## Phase 2: Feature Store

Scope:

1. Add Feast for feature definitions.
2. Offline store from lakehouse/Spark outputs.
3. Online store with Redis.
4. Add validation that train-time and serve-time features are consistent.
5. Keep the online store and UI/API endpoints consistent with the existing dynamic-port strategy.

Success criteria:

1. Single feature definitions reused by training and inference.
2. Online feature retrieval works with low latency.

## Phase 3: Serving and Monitoring

Scope:

1. Add model serving layer (FastAPI/BentoML style service).
2. Add drift/data quality checks (Evidently, Great Expectations style checks).
3. Push monitoring outputs to dashboards (Superset-friendly tables).
4. Keep serving APIs and any UIs optional so the base data engineering stack remains lightweight.

Success criteria:

1. Prediction service has clear version routing.
2. Drift/quality reports generated on schedule.
3. Alerts or reports integrated with existing orchestration.

## Phase 4: AI/LLM Profile (Optional)

Scope:

1. Add optional LLM serving profile (vLLM/OpenAI-compatible API style).
2. Add embedding + retrieval pipeline.
3. Keep this profile opt-in due to resource requirements.
4. Enable only when hardware profile and port allocation are sufficient.

Success criteria:

1. LLM endpoint available only when profile is enabled.
2. Retrieval pipeline reuses existing Spark/Airflow orchestration.

## Proposed Module Layout (Future)

Use the same module pattern already used in this project:

1. `datalabcontainer/app/tech/mlflow/manage.sh`
2. `datalabcontainer/app/tech/featurestore/manage.sh`
3. `datalabcontainer/app/tech/model-serving/manage.sh`
4. `datalabcontainer/app/tech/ai-serving/manage.sh` (optional profile)
5. `datalabcontainer/dev/tech/mlflow/Dockerfile` (or equivalent config folder)
6. `datalabcontainer/dev/tech/model-serving/Dockerfile` (if service image customizations are needed)
7. `datalabcontainer/app/ui_services` entries for any AI/ML UI or API
8. `datalabcontainer/app/start` menu wiring for optional start/stop paths

Related stack examples:

1. `stacks/ml/` for sample train/evaluate/register flows.
2. `stacks/ai/` for retrieval + prompt/inference examples.

## Airflow and Spark Parallelism Model (Important)

Current behavior to preserve and document:

1. Airflow task concurrency and Spark execution capacity are different limits.
2. Airflow tasks can appear `running` while Spark apps wait in queue.
3. Spark worker capacity ultimately controls real concurrent Spark execution.

Example with current defaults:

1. Airflow can run multiple Spark-submit tasks in parallel.
2. Spark executes only as many apps as worker resources allow.
3. Remaining jobs stay queued and run as resources free up.

## Configuration Strategy

1. Add env-driven defaults with safe conservative values.
2. Keep overrides in `.env` and runtime helper commands.
3. Add clear docs for scaling knobs.
Scaling knobs: Airflow concurrency, Spark worker cores and memory, per-app core caps (`spark.cores.max`), and service-specific ports and auth.
4. Prefer using the shared host-port mapping pattern instead of hardcoding external ports in service scripts.

## Resource Profile For This Topology

For the current single-container design, this is the practical target when AI/ML modules are enabled later:

1. Minimum practical expansion target: 12 vCPU, 32 GB RAM, 150 GB SSD
2. Better target for MLflow + feature store + model serving together: 12 to 16 vCPU, 32 to 48 GB RAM, 200 GB SSD
3. Optional local LLM profile target: 16+ vCPU, 48 to 64 GB RAM, 200+ GB SSD, NVIDIA GPU with 12+ GB VRAM

## Risks and Mitigations

1. Resource contention in single-container mode.
Mitigation: keep optional services disabled by default and provide profile-based start commands.

2. Dependency bloat and longer image builds.
Mitigation: phase features, reuse existing base layers, isolate heavy optional dependencies.

3. Operational complexity.
Mitigation: enforce consistent `app/tech/*/manage.sh` pattern and keep startup scripts modular.

4. Broken host links in copied containers.
Mitigation: require all future UI/API surfaces to resolve outside-host URLs from `DATALAB_HOST_PORT_MAP` and display them through `ui_services`.

## Implementation Sequence (When Execution Starts)

1. Implement MLflow module + docs + health check.
2. Add one reference Airflow DAG integrating Spark training and MLflow registration.
3. Add model-serving module.
4. Add feature store module.
5. Add monitoring/quality checks.
6. Add optional AI/LLM profile.

## Out of Scope for This Planning Document

1. Immediate code changes to medilake-specific runtime.
2. GPU-specific production tuning.
3. Multi-node cluster orchestration.

## References

1. MLflow tracking and self-hosting: https://mlflow.org/docs/latest/self-hosting/architecture/tracking-server/
2. Feast feature repository docs: https://docs.feast.dev/reference/feature-repository
3. BentoML docs: https://docs.bentoml.com/
4. FastAPI docs: https://fastapi.tiangolo.com/
5. Evidently docs: https://docs.evidentlyai.com/
6. vLLM OpenAI-compatible server: https://docs.vllm.ai/en/latest/serving/openai_compatible_server.html
