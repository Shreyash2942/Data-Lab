from __future__ import annotations

import os
import redis


def main() -> None:
    port = int(os.getenv("REDIS_PORT", "6379"))
    password = os.getenv("REDIS_PASSWORD", "admin")
    client = redis.Redis(host="localhost", port=port, password=password, decode_responses=True)

    client.hset("pipeline:daily_metrics", mapping={"rows": 1200, "errors": 3, "status": "ok"})
    values = client.hgetall("pipeline:daily_metrics")
    print(values)


if __name__ == "__main__":
    main()
