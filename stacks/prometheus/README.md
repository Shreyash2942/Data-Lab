# Prometheus Stack

This stack documents the embedded Prometheus service used for platform monitoring.

## Runtime Management

- Service module: `datalabcontainer/app/tech/monitoring/`
- Start: `datalab_app --start-prometheus`
- Start full observability stack: `datalab_app --start-observability-stack`

## Endpoints

- Inside container: `http://localhost:9095/`
- Outside host: resolved through `DATALAB_HOST_PORT_MAP`

## Runtime Data

- Config/logs: `~/runtime/monitoring/prometheus/`

## Why This Stack Exists

- Collect time-series metrics and health checks for the Data Lab platform.
- Give the observability stack a stable metrics backend.
- Make it easier to troubleshoot service failures and restarts.

## Common Use Cases

- Check whether monitored services are up.
- Review scrape targets during observability testing.
- Feed Grafana dashboards with metrics from the running stack.

## How To Use In Data Lab

Start Prometheus only:

```bash
datalab_app --start-prometheus
```

Or start the whole observability stack:

```bash
datalab_app --start-observability-stack
```

After it starts, open Prometheus and try the query:

```text
up
```

## Notes

- Prometheus is bundled into the single Data Lab image.
- It scrapes health and metrics endpoints for the current monolithic topology.
