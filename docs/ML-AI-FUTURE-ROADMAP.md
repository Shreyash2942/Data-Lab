# Data Lab Future Roadmap: Machine Learning and AI

This document captures the future implementation plan to extend Data Lab from data engineering into machine learning and AI workloads, without changing the current core topology.

Status: planning only (no implementation in this phase).

## Goals

1. Reuse existing platform building blocks (Airflow, Spark, PostgreSQL, MinIO, Redis, Superset).
2. Add a practical MLOps flow: experiment tracking, model registry, batch/real-time inference.
3. Keep each new capability modular so it can be enabled/disabled per container profile.
4. Preserve current data engineering workflows and scripts.

## Guiding Principles

1. No breaking changes to current ETL and lakehouse stack.
2. New services are optional and start through tech modules, same as existing pattern.
3. Runtime state stays under `~/runtime/<service>`.
4. Keep SQL and Spark flows first-class; ML/AI augments, not replaces, current stack.

## Phase Plan

## Phase 1: MLOps Foundation (Recommended First)

Scope:

1. Add MLflow tracking server.
2. Use PostgreSQL as MLflow backend store.
3. Use MinIO as MLflow artifact store.
4. Add one Airflow DAG for train -> evaluate -> register flow.
5. Add one inference service (batch or API) for registered models.

Success criteria:

1. Experiments and metrics visible in MLflow UI.
2. Model versions promoted through stages (`Staging`, `Production`).
3. Airflow can run end-to-end training + registration pipeline.

## Phase 2: Feature Store

Scope:

1. Add Feast for feature definitions.
2. Offline store from lakehouse/Spark outputs.
3. Online store with Redis.
4. Add validation that train-time and serve-time features are consistent.

Success criteria:

1. Single feature definitions reused by training and inference.
2. Online feature retrieval works with low latency.

## Phase 3: Serving and Monitoring

Scope:

1. Add model serving layer (FastAPI/BentoML style service).
2. Add drift/data quality checks (Evidently, Great Expectations style checks).
3. Push monitoring outputs to dashboards (Superset-friendly tables).

Success criteria:

1. Prediction service has clear version routing.
2. Drift/quality reports generated on schedule.
3. Alerts or reports integrated with existing orchestration.

## Phase 4: AI/LLM Profile (Optional)

Scope:

1. Add optional LLM serving profile (vLLM/OpenAI-compatible API style).
2. Add embedding + retrieval pipeline.
3. Keep this profile opt-in due to resource requirements.

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
3. Add clear docs for scaling knobs:
   - Airflow concurrency knobs
   - Spark worker cores/memory
   - per-app core caps (`spark.cores.max`)
   - service-specific ports and auth

## Risks and Mitigations

1. Resource contention in single-container mode.
Mitigation: keep optional services disabled by default and provide profile-based start commands.

2. Dependency bloat and longer image builds.
Mitigation: phase features, reuse existing base layers, isolate heavy optional dependencies.

3. Operational complexity.
Mitigation: enforce consistent `app/tech/*/manage.sh` pattern and keep startup scripts modular.

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

