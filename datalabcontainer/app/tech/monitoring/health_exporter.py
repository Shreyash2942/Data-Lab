#!/usr/bin/env python3
import os
import socket
import time
import urllib.error
import urllib.request
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer

SERVICE_TARGETS = [
    {'name': 'airflow', 'port': 8080, 'path': '/'},
    {'name': 'spark_master', 'port': 9090, 'path': '/metrics/master/prometheus'},
    {'name': 'spark_worker', 'port': 9091, 'path': '/metrics/prometheus'},
    {'name': 'kafka_ui', 'port': 9002, 'path': '/'},
    {'name': 'schema_registry', 'port': 8085, 'path': '/apis/registry/v3/system/info'},
    {'name': 'kafka_connect', 'port': 8086, 'path': '/connectors'},
    {'name': 'postgres', 'port': 5432},
    {'name': 'mongodb', 'port': 27017},
    {'name': 'redis', 'port': 6379},
    {'name': 'minio', 'port': 9004, 'path': '/minio/health/live'},
    {'name': 'trino', 'port': 8091, 'path': '/v1/info'},
    {'name': 'superset', 'port': 8090, 'path': '/health'},
    {'name': 'jupyterlab', 'port': 8888, 'path': '/login'},
    {'name': 'gx_data_docs', 'port': 8891, 'path': '/'},
    {'name': 'marquez_api', 'port': 5000, 'path': '/api/v1/namespaces'},
    {'name': 'marquez_web', 'port': 3000, 'path': '/healthcheck'},
    {'name': 'prometheus', 'port': 9095, 'path': '/-/healthy'},
    {'name': 'grafana', 'port': 3001, 'path': '/api/health'},
]

HOST = os.environ.get('HEALTH_EXPORTER_HOST', '0.0.0.0')
PORT = int(os.environ.get('HEALTH_EXPORTER_PORT', '9105'))
TIMEOUT_SECONDS = float(os.environ.get('HEALTH_EXPORTER_TIMEOUT', '1.0'))


def check_port(port: int) -> int:
    sock = socket.socket()
    sock.settimeout(TIMEOUT_SECONDS)
    try:
        sock.connect(('127.0.0.1', port))
        return 1
    except OSError:
        return 0
    finally:
        sock.close()


def check_http(port: int, path: str) -> int:
    request = urllib.request.Request(f'http://127.0.0.1:{port}{path}', headers={'User-Agent': 'datalab-health-exporter'})
    try:
        with urllib.request.urlopen(request, timeout=TIMEOUT_SECONDS) as response:
            return 1 if response.status < 500 else 0
    except urllib.error.HTTPError as exc:
        return 1 if exc.code < 500 else 0
    except Exception:
        return 0


class MetricsHandler(BaseHTTPRequestHandler):
    def do_GET(self):
        if self.path == '/health':
            self.send_response(200)
            self.send_header('Content-Type', 'text/plain; charset=utf-8')
            self.end_headers()
            self.wfile.write(b'OK\n')
            return
        if self.path != '/metrics':
            self.send_response(404)
            self.end_headers()
            return

        timestamp = time.time()
        lines = [
            '# HELP datalab_service_port_open Whether the service port is accepting TCP connections.',
            '# TYPE datalab_service_port_open gauge',
            '# HELP datalab_service_up Whether the service health probe succeeded.',
            '# TYPE datalab_service_up gauge',
            '# HELP datalab_service_last_scrape_timestamp_seconds Unix timestamp of the most recent exporter scrape.',
            '# TYPE datalab_service_last_scrape_timestamp_seconds gauge',
        ]

        for target in SERVICE_TARGETS:
            name = target['name']
            port = target['port']
            port_open = check_port(port)
            health_up = check_http(port, target['path']) if target.get('path') else port_open
            lines.append(f'datalab_service_port_open{{service="{name}",port="{port}"}} {port_open}')
            lines.append(f'datalab_service_up{{service="{name}"}} {health_up}')
            lines.append(f'datalab_service_last_scrape_timestamp_seconds{{service="{name}"}} {timestamp:.0f}')

        payload = ('\n'.join(lines) + '\n').encode('utf-8')
        self.send_response(200)
        self.send_header('Content-Type', 'text/plain; version=0.0.4; charset=utf-8')
        self.send_header('Content-Length', str(len(payload)))
        self.end_headers()
        self.wfile.write(payload)

    def log_message(self, fmt, *args):
        return


if __name__ == '__main__':
    server = ThreadingHTTPServer((HOST, PORT), MetricsHandler)
    server.serve_forever()