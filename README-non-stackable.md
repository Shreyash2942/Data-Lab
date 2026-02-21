# Data Lab Non-Stackable Container (Single `docker run`)

Repository layout note:
- Container assets live in `datalabcontainer/`
- Stack examples live in `stacks/`

Quick commands to start Data Lab without Docker Compose stack labels. This runs a single container named `datalab`, maps the project folders into `/home/datalab`, and publishes the common service ports.

## Linux/macOS
```bash
# 1) build or pull the image
docker build -t data-lab:latest .
# or: docker pull yourhubuser/data-lab:latest

# 2) run the container (no Compose stack labels)
NAME=datalab IMAGE=data-lab:latest ./helper/scripts/run-standalone.sh
```

## Windows PowerShell
```powershell
# 1) build or pull the image
docker build -t data-lab:latest .
docker pull yourhubuser/data-lab:latest   # optional alternative

# 2) run the container (root helper wrapper; no Compose stack labels)
powershell -ExecutionPolicy Bypass -File .\helper\scripts\run-standalone.ps1 -Name datalab -Image data-lab:latest

# 3) build + run in one command (root helper wrapper)
powershell -ExecutionPolicy Bypass -File .\helper\scripts\build-and-run.ps1 -Name datalab -Image data-lab:latest

# 4) copy an existing container with prompts for new name + bind mounts
powershell -ExecutionPolicy Bypass -File .\helper\scripts\copy-container.ps1 -SourceName datalab

# 5) show all UI URLs using real mapped host ports
powershell -ExecutionPolicy Bypass -File .\helper\scripts\ui-services.ps1 -Name datalab -UiHost localhost
```

## Notes
- Default ports: 8080 (Airflow), 4040/9090/18080 (Spark), 9092 (Kafka), 9870/8088 (Hadoop), 10000/10001 (Hive), 9002 (Kafdrop), 8082 (Adminer), 8083 (Mongo Express), 8084 (Redis Commander), 8181 (pgAdmin), 5432 (PostgreSQL), 27017 (MongoDB), 6379 (Redis).
- Default mounts map the repo folders into `/home/datalab/...` plus `runtime` for state. Add more with `EXTRA_VOLUMES` (bash) or `-ExtraVolumes` (PowerShell).
- Enter the container: `docker exec -it -w / datalab bash` then `su - datalab` for the dev user.
- Start services from anywhere inside the container with `datalab_app` (equivalent to `bash /home/datalab/app/start`).
- Start database browser UIs from the menu using option `11` or directly with `datalab_app --start-db-uis`.
- Log retention runs automatically before `start`/`restart` commands and removes oldest log files once limits are exceeded.
- Optional tuning env vars: `DATALAB_LOG_RETENTION_ENABLED` (`1`/`0`), `DATALAB_LOG_RETENTION_MAX_TOTAL_MB` (default `1024`), `DATALAB_LOG_RETENTION_MAX_FILES` (default `500`), `DATALAB_LOG_RETENTION_FILE_PATTERNS` (default `*.log *.out *.err`).
- Manual run: `bash /home/datalab/app/start --prune-logs`.
- UI helper command: `ui_services` (or `bash /home/datalab/app/ui_services`) opens an interactive login helper for UIs.
- To print all mapped URLs directly, use: `ui_services --list`.
- Helper folder wrappers (PowerShell): `.\helper\scripts\run-standalone.ps1`, `.\helper\scripts\build-and-run.ps1`, `.\helper\scripts\copy-container.ps1`, `.\helper\scripts\ui-services.ps1`.
- Script source of truth: `.\helper\scripts\*`.

## Database Browser UIs

Start DB services + browser UIs:

```bash
# inside container
datalab_app --start-databases
datalab_app --start-db-uis
```

Per-database guides:

- PostgreSQL: `stacks/postgres/README.md`
- MongoDB: `stacks/mongodb/README.md`
- Redis: `stacks/redis/README.md`

Default `datalab` browser links:

- Adminer (PostgreSQL): `http://localhost:8082/`
- Mongo Express (MongoDB): `http://localhost:8083/`
- Redis Commander (Redis): `http://localhost:8084/`

Copied container example (dynamic mapped ports):

- Adminer: `http://localhost:8085/`
- Mongo Express: `http://localhost:8086/`
- Redis Commander: `http://localhost:8087/`

Use dynamic command any time:

```powershell
powershell -ExecutionPolicy Bypass -File .\helper\scripts\ui-services.ps1 -Name datalab -UiHost localhost
powershell -ExecutionPolicy Bypass -File .\helper\scripts\ui-services.ps1 -Name medilake -UiHost localhost
```

Recommended flow for any user (works with dynamic ports):

1. Start DB services in container:
   ```bash
   datalab_app --start-databases
   datalab_app --start-db-uis
   ```
2. From host, run:
   ```powershell
   powershell -ExecutionPolicy Bypass -File .\helper\scripts\ui-services.ps1 -Name <container-name> -UiHost localhost
   ```
3. Copy the mapped DB/UI ports from that output into browser, VS Code, or PyCharm.

If you want the same PostgreSQL UI style as your existing setup (official pgAdmin4), run:

```powershell
powershell -ExecutionPolicy Bypass -File .\helper\scripts\start-pgadmin.ps1 -TargetContainer datalab -PgAdminPort 8181
```

Then open:

- `http://localhost:8181/`

Default pgAdmin login from helper script:

- Email: `admin@admin.com`
- Password: `root`

## Manual Docker Run (Full Port Mapping)
Use this if you want to create the container directly without helper scripts:

```bash
docker run -d --name datalab \
  --user root \
  --workdir / \
  --label com.docker.compose.project= \
  --label com.docker.compose.service= \
  --label com.docker.compose.oneoff= \
  -p 8080:8080 -p 4040:4040 -p 9090:9090 -p 18080:18080 \
  -p 9092:9092 -p 9870:9870 -p 8088:8088 -p 10000:10000 -p 10001:10001 -p 9002:9002 \
  -p 8082:8082 -p 8083:8083 -p 8084:8084 \
  -p 5432:5432 -p 27017:27017 -p 6379:6379 \
  shreyash42/data-lab:latest \
  sleep infinity
```

Windows PowerShell:

```powershell
docker run -d --name datalab `
  --user root `
  --workdir / `
  --label com.docker.compose.project= `
  --label com.docker.compose.service= `
  --label com.docker.compose.oneoff= `
  -p 8080:8080 -p 4040:4040 -p 9090:9090 -p 18080:18080 `
  -p 9092:9092 -p 9870:9870 -p 8088:8088 -p 10000:10000 -p 10001:10001 -p 9002:9002 `
  -p 8082:8082 -p 8083:8083 -p 8084:8084 `
  -p 5432:5432 -p 27017:27017 -p 6379:6379 `
  shreyash42/data-lab:latest `
  sleep infinity
```


