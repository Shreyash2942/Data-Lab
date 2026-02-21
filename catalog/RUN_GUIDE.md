# Run Guide

## Compose (single container)

```bash
cd datalabcontainer
cp .env.example .env
docker compose build
docker compose up -d
docker compose exec data-lab bash
```

## Service menus (inside container)

```bash
bash ~/app/start
bash ~/app/stop
bash ~/app/restart
bash ~/app/services_demo.sh
```

## Standalone scripts (from repo root)

```bash
bash helper/scripts/run-standalone.sh
```

```powershell
powershell -File .\helper\scripts\run-standalone.ps1
```


