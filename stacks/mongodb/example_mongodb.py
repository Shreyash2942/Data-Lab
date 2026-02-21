from __future__ import annotations

import os
from pymongo import MongoClient


def build_uri() -> str:
    port = os.getenv("MONGO_PORT", "27017")
    user = os.getenv("MONGO_ROOT_USERNAME", "admin")
    password = os.getenv("MONGO_ROOT_PASSWORD", "admin")
    auth_enabled = os.getenv("MONGO_AUTH_ENABLED", "true").lower() == "true"
    if auth_enabled:
        return f"mongodb://{user}:{password}@localhost:{port}/admin?authSource=admin&directConnection=true"
    return f"mongodb://localhost:{port}/?directConnection=true"


def main() -> None:
    db_name = os.getenv("MONGO_DB", "datalab")
    client = MongoClient(build_uri(), serverSelectionTimeoutMS=5000)
    db = client[db_name]
    col = db["ml_experiments"]

    doc = {
        "experiment": "feature_store_baseline",
        "model": "xgboost",
        "accuracy": 0.91,
    }
    col.insert_one(doc)

    for row in col.find({}, {"_id": 0}).sort("experiment", 1):
        print(row)


if __name__ == "__main__":
    main()
