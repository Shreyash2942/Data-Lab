# Data Lab Non-Stackable Container (Single `docker run`)

Quick commands to start Data Lab without Docker Compose stack labels. This runs a single container named `datalab`, maps the project folders into `/home/datalab`, and publishes the common service ports.

## Linux/macOS
```bash
# 1) build or pull the image
docker build -t data-lab:latest .
# or: docker pull yourhubuser/data-lab:latest

# 2) run the container (no Compose stack labels)
NAME=datalab IMAGE=data-lab:latest ./run-standalone.sh
```

## Windows PowerShell
```powershell
# 1) build or pull the image
docker build -t data-lab:latest .
docker pull yourhubuser/data-lab:latest   # optional alternative

# 2) run the container (no Compose stack labels; bypass policy for this run)
powershell -ExecutionPolicy Bypass -File .\run-standalone.ps1 -Name datalab -Image data-lab:latest
```

## Notes
- Default ports: 8080 (Airflow), 4040/9090/18080 (Spark), 9092 (Kafka), 9870/8088 (Hadoop), 10000/10001 (Hive), 9002 (Kafdrop).
- Default mounts map the repo folders into `/home/datalab/...` plus `runtime` for state. Add more with `EXTRA_VOLUMES` (bash) or `-ExtraVolumes` (PowerShell).
- Enter the container: `docker exec -it -w / datalab bash` then `su - datalab` for the dev user.
