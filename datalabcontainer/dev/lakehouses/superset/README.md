# Superset (Lakehouse)

This folder documents Superset usage for the embedded Superset service inside the main `data-lab` container.

- Reference Dockerfile: `datalabcontainer/dev/superset/Dockerfile` (reference only)
- Main runtime build Dockerfile: `datalabcontainer/dev/base/Dockerfile`
- Superset UI: `http://localhost:8090`
- Default login: `admin` / `admin`
- Recommended Trino connection string in Superset:
  `trino://trino@localhost:8091/hive/default`
