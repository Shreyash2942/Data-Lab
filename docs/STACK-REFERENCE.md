# Stack Reference

This page keeps version, image, and build notes in one place so the main README can stay focused on project value and quick onboarding.

## Current Stack Versions

- Spark `3.5.1`
- Hadoop `3.3.6`
- Hive `2.3.9`
- Kafka `3.7.1`
- Kafka Connect `3.7.1`
- Debezium PostgreSQL Connector `3.4.0.Final`
- Apicurio Registry `3.2.0`
- OpenLineage Spark integration `1.38.0`
- Marquez `0.50.0`
- Prometheus `3.2.1`
- Grafana `11.5.2`
- Great Expectations `1.15.0`
- JupyterLab `4.2.7`
- Airflow `2.9.3`
- Hudi `0.15.0`
- Iceberg `1.6.1`
- Delta Lake `3.2.0`
- Trino `435`
- Superset `4.1.2`
- MinIO embedded in the runtime image

## Docker Optimization Notes

- `.dockerignore` excludes runtime state, docs, helpers, and local caches from the build context.
- The base Dockerfile enables `PIP_NO_CACHE_DIR=1` and `PIP_DISABLE_PIP_VERSION_CHECK=1`.
- npm update-notifier and fund prompts are disabled.
- Python installation is consolidated to reduce image layers.
- Service scripts are normalized to avoid Windows CRLF issues on mounted files.

## Recommended Build And Push Approach

- Use `docker buildx` with registry cache in CI.
- Build and push release images from `main` or tags.
- Use branch CI for validation work instead of pushing every build.
- Keep both immutable tags such as `:sha-<commit>` and a rolling tag such as `:latest`.

For step-by-step push and pull instructions, see [Docker Hub Push/Pull Guide](DOCKERHUB-README.md).

## Runtime Image Model

`data-lab:latest` is the main runtime image for the platform.

Some extra images may appear locally during builds, including:

- `prom/prometheus`
- `grafana/grafana`
- `marquezproject/marquez`
- `marquezproject/marquez-web`
- `apicurio/apicurio-registry`
- `quay.io/debezium/connect`

These are build-source images used by the multi-stage Dockerfile. They are not separate runtime containers for Data Lab.

After `data-lab:latest` is built, those images can be removed if nothing else on your machine uses them.

Windows PowerShell cleanup:

```powershell
powershell -ExecutionPolicy Bypass -File .\helper\scripts\cleanup-build-source-images.ps1
```

Dry run:

```powershell
powershell -ExecutionPolicy Bypass -File .\helper\scripts\cleanup-build-source-images.ps1 -DryRun
```

Linux or macOS cleanup:

```bash
bash ./helper/scripts/cleanup-build-source-images.sh
```

Dry run:

```bash
bash ./helper/scripts/cleanup-build-source-images.sh --dry-run
```
