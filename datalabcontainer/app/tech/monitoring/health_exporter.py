#!/usr/bin/env python3
import json
import os
import re
import shutil
import socket
import subprocess
import threading
import time
import urllib.error
import urllib.request
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path
from typing import Callable

HOST = os.environ.get("HEALTH_EXPORTER_HOST", "0.0.0.0")
PORT = int(os.environ.get("HEALTH_EXPORTER_PORT", "9105"))
TIMEOUT_SECONDS = float(os.environ.get("HEALTH_EXPORTER_TIMEOUT", "1.0"))
DEEP_TTL_SECONDS = float(os.environ.get("HEALTH_EXPORTER_DEEP_TTL_SECONDS", "30"))
CLI_TIMEOUT_SECONDS = float(os.environ.get("HEALTH_EXPORTER_CLI_TIMEOUT_SECONDS", "5"))


def env_int(name: str, default: int) -> int:
    raw = str(os.environ.get(name, str(default))).strip()
    try:
        return int(raw)
    except Exception:
        return default


TRINO_USER = os.environ.get("TRINO_USER", "trino")
TRINO_PORT = env_int("TRINO_PORT", 8091)
KAFKA_BROKER_PORT = env_int("KAFKA_BROKER_PORT", 9092)
KAFKA_CONNECT_PORT = env_int("KAFKA_CONNECT_PORT", 8086)
SCHEMA_REGISTRY_PORT = env_int("SCHEMA_REGISTRY_PORT", 8085)
POSTGRES_PORT = env_int("POSTGRES_PORT", 5432)
POSTGRES_USER = os.environ.get("POSTGRES_ADMIN_USER", os.environ.get("POSTGRES_USER", "admin"))
POSTGRES_PASSWORD = os.environ.get(
    "POSTGRES_ADMIN_PASSWORD",
    os.environ.get("POSTGRES_PASSWORD", "admin"),
)
MONGO_PORT = env_int("MONGO_PORT", 27017)
MONGO_USER = os.environ.get("MONGO_ROOT_USERNAME", "admin")
MONGO_PASSWORD = os.environ.get("MONGO_ROOT_PASSWORD", "admin")
REDIS_PORT = env_int("REDIS_PORT", 6379)
REDIS_PASSWORD = os.environ.get("REDIS_PASSWORD", "admin")

AIRFLOW_WEB_PORT = env_int("AIRFLOW_WEB_PORT", 8080)
SPARK_MASTER_UI_PORT = env_int("SPARK_MASTER_WEBUI_PORT", env_int("SPARK_MASTER_UI_PORT", 9090))
SPARK_WORKER_UI_PORT = env_int("SPARK_WORKER_WEBUI_PORT", env_int("SPARK_WORKER_UI_PORT", 9091))
HDFS_NAMENODE_UI_PORT = env_int("HDFS_NAMENODE_UI_PORT", 9870)
YARN_RM_UI_PORT = env_int("YARN_RM_UI_PORT", 8088)
HIVE_METASTORE_PORT = env_int("HIVE_METASTORE_PORT", 9083)
HIVE_SERVER2_THRIFT_PORT = env_int("HIVE_SERVER2_THRIFT_PORT", 10000)
KAFKA_UI_PORT = env_int("KAFKA_UI_PORT", env_int("KAFDROP_PORT", 9002))
PGADMIN_PORT = env_int("PGADMIN_PORT", 8181)
MONGO_EXPRESS_PORT = env_int("MONGO_EXPRESS_PORT", 8083)
REDIS_COMMANDER_PORT = env_int("REDIS_COMMANDER_PORT", 8084)
MINIO_API_PORT = env_int("MINIO_API_PORT", 9004)
SUPERSET_PORT = env_int("SUPERSET_PORT", 8090)
JUPYTER_PORT = env_int("JUPYTER_PORT", 8888)
GX_DOCS_PORT = env_int("GX_DOCS_PORT", 8891)
MARQUEZ_API_PORT = env_int("MARQUEZ_API_PORT", 5000)
MARQUEZ_WEB_PORT = env_int("MARQUEZ_WEB_PORT", 3000)
PROMETHEUS_PORT = env_int("PROMETHEUS_PORT", 9095)
GRAFANA_PORT = env_int("GRAFANA_PORT", 3001)

SERVICE_TARGETS = [
    {"name": "airflow", "scope": "core", "port": AIRFLOW_WEB_PORT, "path": "/"},
    {"name": "spark_master", "scope": "core", "port": SPARK_MASTER_UI_PORT, "path": "/json/"},
    {"name": "spark_worker", "scope": "core", "port": SPARK_WORKER_UI_PORT, "path": "/metrics/prometheus"},
    {"name": "hdfs_namenode", "scope": "core", "port": HDFS_NAMENODE_UI_PORT, "path": "/"},
    {"name": "yarn_resourcemanager", "scope": "core", "port": YARN_RM_UI_PORT, "path": "/ws/v1/cluster/info"},
    {"name": "hive_metastore", "scope": "core", "port": HIVE_METASTORE_PORT},
    {"name": "hive_hs2", "scope": "core", "port": HIVE_SERVER2_THRIFT_PORT},
    {"name": "kafka_broker", "scope": "core", "port": KAFKA_BROKER_PORT},
    {"name": "kafka_ui", "scope": "core", "port": KAFKA_UI_PORT, "path": "/"},
    {"name": "schema_registry", "scope": "core", "port": SCHEMA_REGISTRY_PORT, "path": "/apis/registry/v3/system/info"},
    {"name": "kafka_connect", "scope": "core", "port": KAFKA_CONNECT_PORT, "path": "/connectors"},
    {"name": "postgres", "scope": "databases", "port": POSTGRES_PORT},
    {"name": "mongodb", "scope": "databases", "port": MONGO_PORT},
    {"name": "redis", "scope": "databases", "port": REDIS_PORT},
    {"name": "pgadmin", "scope": "databases", "port": PGADMIN_PORT, "path": "/"},
    {"name": "mongo_express", "scope": "databases", "port": MONGO_EXPRESS_PORT, "path": "/"},
    {"name": "redis_commander", "scope": "databases", "port": REDIS_COMMANDER_PORT, "path": "/"},
    {"name": "minio", "scope": "lakehouse", "port": MINIO_API_PORT, "path": "/minio/health/live"},
    {"name": "trino", "scope": "lakehouse", "port": TRINO_PORT, "path": "/v1/info"},
    {"name": "superset", "scope": "lakehouse", "port": SUPERSET_PORT, "path": "/health"},
    {"name": "jupyterlab", "scope": "quality", "port": JUPYTER_PORT, "path": "/login"},
    {"name": "gx_data_docs", "scope": "quality", "port": GX_DOCS_PORT, "path": "/"},
    {"name": "marquez_api", "scope": "observability", "port": MARQUEZ_API_PORT, "path": "/api/v1/namespaces"},
    {"name": "marquez_web", "scope": "observability", "port": MARQUEZ_WEB_PORT, "path": "/healthcheck"},
    {"name": "prometheus", "scope": "observability", "port": PROMETHEUS_PORT, "path": "/-/healthy"},
    {"name": "grafana", "scope": "observability", "port": GRAFANA_PORT, "path": "/api/health"},
]

SCOPE_NAMES = ("all", "core", "databases", "lakehouse", "quality", "observability")

RUNTIME_NAME_PATTERN = re.compile(
    r"^(python([0-9.]+)?|pypy([0-9.]+)?|java|javac|scala|sbt|node|npm|npx|go|rustc|cargo|"
    r"ruby|perl|php|julia|R|kotlin|groovy|clojure|lua|dotnet|swift|bash|sh|zsh|fish|pwsh|"
    r"powershell|trino|hive|beeline|spark-submit)$",
    re.IGNORECASE,
)

VERSION_ARGS_BY_CMD = {
    "java": ["-version"],
    "javac": ["-version"],
    "node": ["--version"],
    "npm": ["--version"],
    "npx": ["--version"],
    "python": ["--version"],
    "python3": ["--version"],
    "ruby": ["--version"],
    "perl": ["--version"],
    "php": ["--version"],
    "go": ["version"],
    "rustc": ["--version"],
    "cargo": ["--version"],
    "dotnet": ["--version"],
    "swift": ["--version"],
    "bash": ["--version"],
    "zsh": ["--version"],
    "fish": ["--version"],
    "pwsh": ["--version"],
    "powershell": ["--version"],
    "spark-submit": ["--version"],
    "hive": ["--version"],
    "beeline": ["--version"],
    "trino": ["--version"],
    "scala": ["--version"],
    "sbt": ["--version"],
}

METRIC_HELP = {
    "datalab_service_info": "Static service descriptor for Data Lab services.",
    "datalab_service_port_open": "Whether the service port is accepting TCP connections.",
    "datalab_service_up": "Whether the service health probe succeeded.",
    "datalab_service_last_scrape_timestamp_seconds": "Unix timestamp of the most recent service scrape.",
    "datalab_services_total": "Total number of tracked services in the scope.",
    "datalab_services_running": "Number of healthy/running services in the scope.",
    "datalab_services_down": "Number of unhealthy/down services in the scope.",
    "datalab_probe_success": "Whether a deep probe succeeded on its last execution.",
    "datalab_probe_last_duration_seconds": "Duration of the last deep probe execution.",
    "datalab_spark_active_apps": "Number of active Spark applications.",
    "datalab_spark_completed_apps": "Number of completed Spark applications.",
    "datalab_spark_active_drivers": "Number of active Spark drivers.",
    "datalab_spark_alive_workers": "Number of alive Spark workers.",
    "datalab_spark_cores_used": "Total Spark cores currently used.",
    "datalab_spark_cores_total": "Total Spark cores available.",
    "datalab_yarn_apps_running": "Number of running YARN applications.",
    "datalab_yarn_apps_pending": "Number of pending YARN applications.",
    "datalab_yarn_apps_completed": "Number of completed YARN applications.",
    "datalab_yarn_nodes_active": "Number of active YARN nodes.",
    "datalab_yarn_nodes_unhealthy": "Number of unhealthy YARN nodes.",
    "datalab_hive_daemon_up": "Hive daemon health (metastore/hs2).",
    "datalab_hive_jobs_running_inferred": "Inferred count of running Hive/Tez jobs from YARN apps.",
    "datalab_kafka_topics_total": "Total number of Kafka topics.",
    "datalab_kafka_consumer_groups_total": "Total number of Kafka consumer groups.",
    "datalab_kafka_connectors_total": "Total number of Kafka Connect connectors.",
    "datalab_kafka_connectors_running": "Number of running Kafka Connect connectors.",
    "datalab_kafka_connect_tasks_running": "Number of running Kafka Connect tasks.",
    "datalab_postgres_connections_active": "Active PostgreSQL connections.",
    "datalab_postgres_connections_idle": "Idle PostgreSQL connections.",
    "datalab_postgres_connections_max": "Configured PostgreSQL max connections.",
    "datalab_mongodb_databases_total": "Total MongoDB database count.",
    "datalab_mongodb_collections_total": "Total MongoDB collection count.",
    "datalab_mongodb_ops_in_progress": "MongoDB operations currently in progress.",
    "datalab_redis_connected_clients": "Redis connected clients.",
    "datalab_redis_used_memory_bytes": "Redis used memory in bytes.",
    "datalab_redis_blocked_clients": "Redis blocked clients.",
    "datalab_redis_keys_total": "Total Redis keys in DB 0.",
    "datalab_trino_queries_running": "Running Trino queries.",
    "datalab_trino_queries_queued": "Queued Trino queries.",
    "datalab_trino_queries_failed": "Failed Trino queries currently present in runtime view.",
    "datalab_lakehouse_tables_total": "Lakehouse table inventory by engine/schema.",
    "datalab_runtime_language_info": "Detected runtime/language tool available in PATH.",
}

MetricSample = tuple[str, dict[str, str], float]

PROBE_CACHE_LOCK = threading.Lock()
PROBE_CACHE: dict[str, dict[str, object]] = {}


def build_probe_cache_record(
    timestamp: float,
    duration_seconds: float,
    success: int,
    samples: list[MetricSample],
) -> dict[str, object]:
    return {
        "timestamp": timestamp,
        "duration_seconds": duration_seconds,
        "success": success,
        "samples": samples,
    }


def escape_label_value(value: str) -> str:
    return value.replace("\\", "\\\\").replace('"', '\\"')


def metric_sample(name: str, value: float, **labels: str) -> MetricSample:
    return name, labels, float(value)


def format_metric_line(name: str, labels: dict[str, str], value: float) -> str:
    if labels:
        labels_blob = ",".join(f'{k}="{escape_label_value(v)}"' for k, v in sorted(labels.items()))
        return f"{name}{{{labels_blob}}} {value:g}"
    return f"{name} {value:g}"


def check_port(port: int) -> int:
    sock = socket.socket()
    sock.settimeout(TIMEOUT_SECONDS)
    try:
        sock.connect(("127.0.0.1", port))
        return 1
    except OSError:
        return 0
    finally:
        sock.close()


def http_request(path: str, port: int, expected_json: bool = False) -> object:
    request = urllib.request.Request(
        f"http://127.0.0.1:{port}{path}",
        headers={"User-Agent": "datalab-health-exporter"},
    )
    with urllib.request.urlopen(request, timeout=TIMEOUT_SECONDS) as response:
        payload = response.read()
    if expected_json:
        return json.loads(payload.decode("utf-8"))
    return payload.decode("utf-8", errors="replace")


def check_http(port: int, path: str) -> int:
    request = urllib.request.Request(
        f"http://127.0.0.1:{port}{path}",
        headers={"User-Agent": "datalab-health-exporter"},
    )
    try:
        with urllib.request.urlopen(request, timeout=TIMEOUT_SECONDS) as response:
            return 1 if response.status < 500 else 0
    except urllib.error.HTTPError as exc:
        return 1 if exc.code < 500 else 0
    except Exception:
        return 0


def run_command(command: list[str], env: dict[str, str] | None = None, timeout: float | None = None) -> str:
    output = subprocess.check_output(
        command,
        stderr=subprocess.STDOUT,
        text=True,
        env=env,
        timeout=timeout if timeout is not None else CLI_TIMEOUT_SECONDS,
    )
    return output.strip()


def count_nonempty_lines(text: str) -> int:
    return sum(1 for line in text.splitlines() if line.strip())


def first_line(text: str) -> str:
    lines = [line.strip() for line in text.splitlines() if line.strip()]
    return lines[0] if lines else ""


def pick_command(name: str, fallback_path: str | None = None) -> str:
    found = shutil.which(name)
    if found:
        return found
    if fallback_path and Path(fallback_path).exists():
        return fallback_path
    raise FileNotFoundError(f"missing command: {name}")


def extract_int(value: object, default: int = 0) -> int:
    if value is None:
        return default
    try:
        return int(float(str(value).strip()))
    except Exception:
        return default


def trino_query(sql: str) -> list[list[object]]:
    url = f"http://127.0.0.1:{TRINO_PORT}/v1/statement"
    request = urllib.request.Request(url, data=sql.encode("utf-8"), method="POST")
    request.add_header("X-Trino-User", TRINO_USER)
    request.add_header("X-Trino-Catalog", "system")
    request.add_header("X-Trino-Schema", "runtime")
    request.add_header("Content-Type", "text/plain; charset=utf-8")

    rows: list[list[object]] = []
    with urllib.request.urlopen(request, timeout=CLI_TIMEOUT_SECONDS) as response:
        payload = json.loads(response.read().decode("utf-8"))

    while True:
        if payload.get("error"):
            raise RuntimeError(payload["error"].get("message", "unknown Trino error"))
        rows.extend(payload.get("data", []))
        next_uri = payload.get("nextUri")
        if not next_uri:
            break
        poll = urllib.request.Request(next_uri, method="GET")
        poll.add_header("X-Trino-User", TRINO_USER)
        with urllib.request.urlopen(poll, timeout=CLI_TIMEOUT_SECONDS) as response:
            payload = json.loads(response.read().decode("utf-8"))
    return rows


def execute_deep_probe(name: str, callback: Callable[[], list[MetricSample]]) -> tuple[list[MetricSample], int, float]:
    now = time.time()
    with PROBE_CACHE_LOCK:
        cache_record = PROBE_CACHE.get(name)

    if cache_record and (now - float(cache_record["timestamp"])) < DEEP_TTL_SECONDS:
        return (
            list(cache_record["samples"]),  # type: ignore[arg-type]
            int(cache_record["success"]),  # type: ignore[arg-type]
            float(cache_record["duration_seconds"]),  # type: ignore[arg-type]
        )

    start = time.perf_counter()
    success = 1
    samples: list[MetricSample]
    try:
        samples = callback()
    except Exception:
        success = 0
        samples = list(cache_record["samples"]) if cache_record else []  # type: ignore[arg-type]
    duration = time.perf_counter() - start

    with PROBE_CACHE_LOCK:
        PROBE_CACHE[name] = build_probe_cache_record(now, duration, success, samples)

    return samples, success, duration


def probe_spark() -> list[MetricSample]:
    payload = http_request("/json/", SPARK_MASTER_UI_PORT, expected_json=True)
    if not isinstance(payload, dict):
        raise RuntimeError("unexpected Spark master payload")

    return [
        metric_sample("datalab_spark_active_apps", len(payload.get("activeapps", []))),
        metric_sample("datalab_spark_completed_apps", len(payload.get("completedapps", []))),
        metric_sample("datalab_spark_active_drivers", len(payload.get("activedrivers", []))),
        metric_sample("datalab_spark_alive_workers", extract_int(payload.get("aliveworkers"), len(payload.get("workers", [])))),
        metric_sample("datalab_spark_cores_used", extract_int(payload.get("coresused"))),
        metric_sample("datalab_spark_cores_total", extract_int(payload.get("cores"))),
    ]


def probe_yarn() -> list[MetricSample]:
    payload = http_request("/ws/v1/cluster/metrics", YARN_RM_UI_PORT, expected_json=True)
    metrics = payload.get("clusterMetrics", {}) if isinstance(payload, dict) else {}
    if not isinstance(metrics, dict):
        raise RuntimeError("unexpected YARN metrics payload")
    return [
        metric_sample("datalab_yarn_apps_running", extract_int(metrics.get("appsRunning"))),
        metric_sample("datalab_yarn_apps_pending", extract_int(metrics.get("appsPending"))),
        metric_sample("datalab_yarn_apps_completed", extract_int(metrics.get("appsCompleted"))),
        metric_sample("datalab_yarn_nodes_active", extract_int(metrics.get("activeNodes"))),
        metric_sample("datalab_yarn_nodes_unhealthy", extract_int(metrics.get("unhealthyNodes"))),
    ]


def probe_hive_jobs() -> list[MetricSample]:
    payload = http_request("/ws/v1/cluster/apps?states=RUNNING", YARN_RM_UI_PORT, expected_json=True)
    apps_section = payload.get("apps", {}) if isinstance(payload, dict) else {}
    running_apps = apps_section.get("app", []) if isinstance(apps_section, dict) else []
    if not isinstance(running_apps, list):
        running_apps = []

    inferred_count = 0
    for app in running_apps:
        if not isinstance(app, dict):
            continue
        app_name = str(app.get("name", "")).lower()
        app_type = str(app.get("applicationType", "")).lower()
        if "hive" in app_name or "tez" in app_name:
            inferred_count += 1
            continue
        if app_type in ("hive", "tez"):
            inferred_count += 1
            continue
        if app_type == "mapreduce" and ("hive" in app_name or "tez" in app_name):
            inferred_count += 1

    return [metric_sample("datalab_hive_jobs_running_inferred", inferred_count)]


def probe_kafka_cli() -> list[MetricSample]:
    topics_cmd = pick_command("kafka-topics.sh", "/opt/kafka/bin/kafka-topics.sh")
    groups_cmd = pick_command("kafka-consumer-groups.sh", "/opt/kafka/bin/kafka-consumer-groups.sh")

    topics_output = run_command([topics_cmd, "--bootstrap-server", f"localhost:{KAFKA_BROKER_PORT}", "--list"])
    groups_output = run_command([groups_cmd, "--bootstrap-server", f"localhost:{KAFKA_BROKER_PORT}", "--list"])

    return [
        metric_sample("datalab_kafka_topics_total", count_nonempty_lines(topics_output)),
        metric_sample("datalab_kafka_consumer_groups_total", count_nonempty_lines(groups_output)),
    ]


def probe_kafka_connect() -> list[MetricSample]:
    connectors_payload = http_request("/connectors", KAFKA_CONNECT_PORT, expected_json=True)
    connectors = connectors_payload if isinstance(connectors_payload, list) else []
    connector_running = 0
    tasks_running = 0

    for connector_name in connectors:
        status_payload = http_request(f"/connectors/{connector_name}/status", KAFKA_CONNECT_PORT, expected_json=True)
        connector_state = str(status_payload.get("connector", {}).get("state", "")).upper() if isinstance(status_payload, dict) else ""
        if connector_state == "RUNNING":
            connector_running += 1
        for task in status_payload.get("tasks", []) if isinstance(status_payload, dict) else []:
            if str(task.get("state", "")).upper() == "RUNNING":
                tasks_running += 1

    return [
        metric_sample("datalab_kafka_connectors_total", len(connectors)),
        metric_sample("datalab_kafka_connectors_running", connector_running),
        metric_sample("datalab_kafka_connect_tasks_running", tasks_running),
    ]


def probe_postgres() -> list[MetricSample]:
    psql_cmd = pick_command("psql")
    env = dict(os.environ)
    env["PGPASSWORD"] = POSTGRES_PASSWORD
    sql = (
        "SELECT "
        "COALESCE(sum((state='active')::int),0),"
        "COALESCE(sum((state='idle')::int),0),"
        "current_setting('max_connections')::int "
        "FROM pg_stat_activity;"
    )
    output = run_command(
        [psql_cmd, "-h", "127.0.0.1", "-p", str(POSTGRES_PORT), "-U", POSTGRES_USER, "-d", "postgres", "-At", "-F", ",", "-c", sql],
        env=env,
    )
    parts = output.split(",")
    if len(parts) != 3:
        raise RuntimeError("unexpected PostgreSQL probe output")
    active, idle, max_connections = (extract_int(value) for value in parts)
    return [
        metric_sample("datalab_postgres_connections_active", active),
        metric_sample("datalab_postgres_connections_idle", idle),
        metric_sample("datalab_postgres_connections_max", max_connections),
    ]


def probe_mongodb() -> list[MetricSample]:
    mongosh_cmd = pick_command("mongosh", "/opt/mongosh/bin/mongosh")
    script = (
        "const admin=db.getSiblingDB('admin');"
        "const dbs=admin.adminCommand({listDatabases:1});"
        "const status=admin.runCommand({serverStatus:1});"
        "let collections=0;"
        "for (const d of (dbs.databases||[])) {"
        "  try { collections += admin.getSiblingDB(d.name).getCollectionInfos().length; } catch(e) {}"
        "}"
        "const ops=((status.globalLock||{}).currentQueue||{}).total||0;"
        "print(JSON.stringify({databases:(dbs.databases||[]).length,collections:collections,ops:ops}));"
    )

    common_prefix = [mongosh_cmd, "--quiet", "--host", "127.0.0.1", "--port", str(MONGO_PORT)]
    auth_cmd = common_prefix + ["-u", MONGO_USER, "-p", MONGO_PASSWORD, "--authenticationDatabase", "admin", "--eval", script]
    noauth_cmd = common_prefix + ["--eval", script]

    output = ""
    try:
        output = run_command(auth_cmd)
    except Exception:
        output = run_command(noauth_cmd)

    parsed = json.loads(first_line(output) or "{}")
    return [
        metric_sample("datalab_mongodb_databases_total", extract_int(parsed.get("databases"))),
        metric_sample("datalab_mongodb_collections_total", extract_int(parsed.get("collections"))),
        metric_sample("datalab_mongodb_ops_in_progress", extract_int(parsed.get("ops"))),
    ]


def probe_redis() -> list[MetricSample]:
    redis_cmd = pick_command("redis-cli")

    def run_redis(args: list[str]) -> str:
        auth_cmd = [redis_cmd, "-h", "127.0.0.1", "-p", str(REDIS_PORT), "-a", REDIS_PASSWORD, "--no-auth-warning"] + args
        try:
            return run_command(auth_cmd)
        except Exception:
            plain_cmd = [redis_cmd, "-h", "127.0.0.1", "-p", str(REDIS_PORT)] + args
            return run_command(plain_cmd)

    info_output = run_redis(["INFO"])
    dbsize_output = run_redis(["DBSIZE"])
    info_map: dict[str, str] = {}
    for line in info_output.splitlines():
        if not line or line.startswith("#") or ":" not in line:
            continue
        key, value = line.split(":", 1)
        info_map[key.strip()] = value.strip()

    return [
        metric_sample("datalab_redis_connected_clients", extract_int(info_map.get("connected_clients"))),
        metric_sample("datalab_redis_used_memory_bytes", extract_int(info_map.get("used_memory"))),
        metric_sample("datalab_redis_blocked_clients", extract_int(info_map.get("blocked_clients"))),
        metric_sample("datalab_redis_keys_total", extract_int(first_line(dbsize_output))),
    ]


def probe_trino() -> list[MetricSample]:
    rows = trino_query(
        "SELECT "
        "sum(CASE WHEN state = 'RUNNING' THEN 1 ELSE 0 END),"
        "sum(CASE WHEN state = 'QUEUED' THEN 1 ELSE 0 END),"
        "sum(CASE WHEN state = 'FAILED' THEN 1 ELSE 0 END) "
        "FROM system.runtime.queries"
    )
    if not rows:
        raise RuntimeError("empty Trino query response")
    running, queued, failed = (extract_int(value) for value in rows[0])
    return [
        metric_sample("datalab_trino_queries_running", running),
        metric_sample("datalab_trino_queries_queued", queued),
        metric_sample("datalab_trino_queries_failed", failed),
    ]


def probe_lakehouse_inventory() -> list[MetricSample]:
    samples: list[MetricSample] = []
    targets = [
        ("iceberg", "demo_iceberg"),
        ("delta", "demo_delta"),
        ("hudi", "demo_hudi"),
    ]
    for engine, schema in targets:
        rows = trino_query(
            f"SELECT count(*) FROM {engine}.information_schema.tables WHERE table_schema = '{schema}'"
        )
        count = extract_int(rows[0][0]) if rows else 0
        samples.append(metric_sample("datalab_lakehouse_tables_total", count, engine=engine, schema=schema))
    return samples


def discover_runtime_commands() -> list[str]:
    discovered = set()
    for path_dir in os.environ.get("PATH", "").split(os.pathsep):
        if not path_dir:
            continue
        path = Path(path_dir)
        if not path.is_dir():
            continue
        try:
            for item in path.iterdir():
                if not item.is_file():
                    continue
                if not os.access(item, os.X_OK):
                    continue
                name = item.name
                if RUNTIME_NAME_PATTERN.match(name):
                    discovered.add(name)
        except OSError:
            continue

    for common in (
        "python3",
        "python",
        "java",
        "javac",
        "scala",
        "node",
        "npm",
        "go",
        "rustc",
        "cargo",
        "bash",
        "sh",
        "hive",
        "beeline",
        "spark-submit",
        "trino",
    ):
        if shutil.which(common):
            discovered.add(common)
    return sorted(discovered)


def probe_runtime_languages() -> list[MetricSample]:
    samples: list[MetricSample] = []
    for runtime in discover_runtime_commands():
        runtime_path = shutil.which(runtime)
        if not runtime_path:
            continue
        version_args = VERSION_ARGS_BY_CMD.get(runtime.lower(), ["--version"])
        version = "unknown"
        try:
            raw = run_command([runtime, *version_args], timeout=min(CLI_TIMEOUT_SECONDS, 5.0))
            version = first_line(raw) or "unknown"
        except subprocess.TimeoutExpired:
            version = "timeout"
        except subprocess.CalledProcessError as exc:
            version = first_line(exc.output) or "error"
        except Exception:
            version = "error"

        sanitized_version = re.sub(r"\s+", " ", version).strip()
        if not sanitized_version:
            sanitized_version = "unknown"
        samples.append(
            metric_sample(
                "datalab_runtime_language_info",
                1.0,
                runtime=runtime,
                version=sanitized_version[:120],
                path=runtime_path,
            )
        )
    return samples


DEEP_PROBES: dict[str, Callable[[], list[MetricSample]]] = {
    "spark_api": probe_spark,
    "yarn_api": probe_yarn,
    "hive_jobs_inferred": probe_hive_jobs,
    "kafka_cli": probe_kafka_cli,
    "kafka_connect_api": probe_kafka_connect,
    "postgres_probe": probe_postgres,
    "mongodb_probe": probe_mongodb,
    "redis_probe": probe_redis,
    "trino_probe": probe_trino,
    "lakehouse_inventory": probe_lakehouse_inventory,
    "runtime_languages": probe_runtime_languages,
}


def build_service_samples(scrape_timestamp: float) -> tuple[list[MetricSample], dict[str, int]]:
    samples: list[MetricSample] = []
    service_status: dict[str, int] = {}

    for target in SERVICE_TARGETS:
        name = str(target["name"])
        scope = str(target["scope"])
        port = int(target["port"])
        labels = {"service": name, "scope": scope, "port": str(port)}

        port_open = check_port(port)
        health_up = check_http(port, str(target.get("path", "/"))) if target.get("path") else port_open
        service_status[name] = int(health_up)

        samples.append(metric_sample("datalab_service_info", 1, **labels))
        samples.append(metric_sample("datalab_service_port_open", port_open, **labels))
        samples.append(metric_sample("datalab_service_up", health_up, **labels))
        samples.append(metric_sample("datalab_service_last_scrape_timestamp_seconds", scrape_timestamp, **labels))

    for scope in SCOPE_NAMES:
        scoped_targets = SERVICE_TARGETS if scope == "all" else [t for t in SERVICE_TARGETS if t["scope"] == scope]
        total = len(scoped_targets)
        running = sum(service_status.get(str(target["name"]), 0) for target in scoped_targets)
        down = total - running
        scope_labels = {"scope": scope}
        samples.append(metric_sample("datalab_services_total", total, **scope_labels))
        samples.append(metric_sample("datalab_services_running", running, **scope_labels))
        samples.append(metric_sample("datalab_services_down", down, **scope_labels))

    samples.append(metric_sample("datalab_hive_daemon_up", service_status.get("hive_metastore", 0), daemon="metastore"))
    samples.append(metric_sample("datalab_hive_daemon_up", service_status.get("hive_hs2", 0), daemon="hiveserver2"))
    return samples, service_status


class MetricsHandler(BaseHTTPRequestHandler):
    def do_GET(self) -> None:
        if self.path == "/health":
            self.send_response(200)
            self.send_header("Content-Type", "text/plain; charset=utf-8")
            self.end_headers()
            self.wfile.write(b"OK\n")
            return

        if self.path != "/metrics":
            self.send_response(404)
            self.end_headers()
            return

        scrape_timestamp = time.time()
        samples: list[MetricSample] = []
        service_samples, _ = build_service_samples(scrape_timestamp)
        samples.extend(service_samples)

        for probe_name, probe_fn in DEEP_PROBES.items():
            probe_samples, probe_success, probe_duration = execute_deep_probe(probe_name, probe_fn)
            samples.extend(probe_samples)
            samples.append(metric_sample("datalab_probe_success", probe_success, probe=probe_name))
            samples.append(metric_sample("datalab_probe_last_duration_seconds", probe_duration, probe=probe_name))

        lines: list[str] = []
        for metric_name, help_text in METRIC_HELP.items():
            lines.append(f"# HELP {metric_name} {help_text}")
            lines.append(f"# TYPE {metric_name} gauge")
        for metric_name, labels, value in samples:
            lines.append(format_metric_line(metric_name, labels, value))

        payload = ("\n".join(lines) + "\n").encode("utf-8")
        self.send_response(200)
        self.send_header("Content-Type", "text/plain; version=0.0.4; charset=utf-8")
        self.send_header("Content-Length", str(len(payload)))
        self.end_headers()
        self.wfile.write(payload)

    def log_message(self, fmt: str, *args: object) -> None:
        return


if __name__ == "__main__":
    server = ThreadingHTTPServer((HOST, PORT), MetricsHandler)
    server.serve_forever()
