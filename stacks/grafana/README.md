# Grafana Stack

This stack documents the embedded Grafana UI used for monitoring dashboards.

## Runtime Management

- Service module: `datalabcontainer/app/tech/monitoring/`
- Start: `datalab_app --start-grafana`
- Start full observability stack: `datalab_app --start-observability-stack`

## Endpoints

- Inside container: `http://localhost:3001/`
- Outside host: resolved through `DATALAB_HOST_PORT_MAP`

## Default Login

- Username: `admin`
- Password: `admin`

## Runtime Data

- Dashboards/logs: `~/runtime/monitoring/grafana/`

## Why This Stack Exists

- Turn raw Prometheus metrics into dashboards the team can read quickly.
- Provide a simple operational UI for stack health and observability demos.
- Make monitoring easier than querying raw metrics by hand.

## Common Use Cases

- Review the provisioned Data Lab overview dashboard.
- Check service health during platform startup and validation.
- Share a simple monitoring view during demos or troubleshooting.
- Track time-series metrics such as pipeline freshness, job counts, lag, latency, and resource usage.

## Best Fit For Dashboarding

Grafana is the best fit in Data Lab when you want:

- Operational dashboards
- Monitoring and alerting views
- Time-series charts
- Service and pipeline health reporting
- Spark, Airflow, Kafka, Prometheus, and infrastructure metrics in one place

For curated dataset analytics, SQL exploration, or business-style BI dashboards over dbt/Hive/Trino models, Superset is usually the better fit.

## How To Use In Data Lab

Start Grafana only:

```bash
datalab_app --start-grafana
```

Or start the full observability stack:

```bash
datalab_app --start-observability-stack
```

Default login:

```text
admin / admin
```

## Notes

- Grafana dashboards are provisioned inside the main Data Lab image.
- It is paired with Prometheus in the observability stack.
