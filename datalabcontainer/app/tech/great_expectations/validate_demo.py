#!/usr/bin/env python3
import json
import os
import sys
from pathlib import Path

import pandas as pd

import great_expectations as gx
import great_expectations.expectations as gxe


PROJECT_ROOT = Path(
    os.environ.get(
        "GX_PROJECT_ROOT",
        "/home/datalab/runtime/great_expectations/project",
    )
).resolve()
DATA_DIR = Path(
    os.environ.get(
        "GX_DATA_DIR",
        "/home/datalab/runtime/great_expectations/demo_data",
    )
).resolve()
RESULT_PATH = Path(
    os.environ.get(
        "GX_RESULT_JSON",
        "/home/datalab/runtime/great_expectations/last_validation.json",
    )
).resolve()

DATASOURCE_NAME = "phase3_quality_datasource"
DATA_ASSET_NAME = "customer_events_dataframe"
BATCH_DEFINITION_NAME = "whole_dataframe"
SUITE_NAME = "phase3_quality_suite"
VALIDATION_DEFINITION_NAME = "phase3_quality_validation"
CHECKPOINT_NAME = "phase3_quality_checkpoint"
CSV_PATH = DATA_DIR / "customer_events_quality.csv"


def write_result(payload: dict) -> None:
    RESULT_PATH.parent.mkdir(parents=True, exist_ok=True)
    RESULT_PATH.write_text(json.dumps(payload, indent=2), encoding="utf-8")


def extract_index_path(obj) -> str:
    if isinstance(obj, dict):
        for value in obj.values():
            path = extract_index_path(value)
            if path:
                return path
        return ""
    if isinstance(obj, (list, tuple)):
        for value in obj:
            path = extract_index_path(value)
            if path:
                return path
        return ""
    if isinstance(obj, str) and obj.endswith("index.html"):
        return obj
    return ""


def normalize_index_path(raw_path: str) -> Path:
    if raw_path.startswith("file://"):
        raw_path = raw_path[7:]
    if not raw_path:
        raise ValueError("Great Expectations did not return a Data Docs index path")
    return Path(raw_path).resolve()


def create_demo_csv() -> None:
    DATA_DIR.mkdir(parents=True, exist_ok=True)
    df = pd.DataFrame(
        [
            {
                "customer_id": 101,
                "event_type": "created",
                "order_total": 125.50,
                "event_date": "2026-03-16",
                "status": "new",
            },
            {
                "customer_id": 102,
                "event_type": "updated",
                "order_total": 89.99,
                "event_date": "2026-03-16",
                "status": "active",
            },
            {
                "customer_id": 103,
                "event_type": "updated",
                "order_total": 410.00,
                "event_date": "2026-03-17",
                "status": "active",
            },
            {
                "customer_id": 104,
                "event_type": "refunded",
                "order_total": 42.25,
                "event_date": "2026-03-17",
                "status": "review",
            },
            {
                "customer_id": 105,
                "event_type": "closed",
                "order_total": 18.00,
                "event_date": "2026-03-18",
                "status": "closed",
            },
        ]
    )
    df.to_csv(CSV_PATH, index=False)


def get_or_create_context():
    PROJECT_ROOT.mkdir(parents=True, exist_ok=True)
    os.environ.setdefault("GX_ANALYTICS_ENABLED", "False")
    try:
        return gx.get_context(mode="file", project_root_dir=str(PROJECT_ROOT))
    except TypeError:
        return gx.get_context(project_root_dir=str(PROJECT_ROOT))


def get_or_create_datasource(context):
    try:
        return context.data_sources.get(DATASOURCE_NAME)
    except Exception:
        return context.data_sources.add_pandas(name=DATASOURCE_NAME)


def get_or_create_asset(data_source):
    try:
        return data_source.get_asset(DATA_ASSET_NAME)
    except Exception:
        return data_source.add_dataframe_asset(name=DATA_ASSET_NAME)


def get_or_create_batch_definition(asset):
    try:
        return asset.get_batch_definition(BATCH_DEFINITION_NAME)
    except Exception:
        return asset.add_batch_definition_whole_dataframe(BATCH_DEFINITION_NAME)


def build_suite(context):
    suite = gx.ExpectationSuite(name=SUITE_NAME)
    suite.add_expectation(
        gxe.ExpectTableColumnsToMatchSet(
            column_set=[
                "customer_id",
                "event_type",
                "order_total",
                "event_date",
                "status",
            ],
            exact_match=True,
        )
    )
    suite.add_expectation(gxe.ExpectColumnValuesToNotBeNull(column="customer_id"))
    suite.add_expectation(
        gxe.ExpectColumnValuesToBeInSet(
            column="status",
            value_set=["new", "active", "review", "closed"],
        )
    )
    suite.add_expectation(
        gxe.ExpectColumnValuesToBeBetween(
            column="order_total",
            min_value=0,
            max_value=10000,
        )
    )
    suite.add_expectation(gxe.ExpectTableRowCountToEqual(value=5))
    return context.suites.add_or_update(suite)


def build_validation_definition(context, batch_definition, suite):
    validation_definition = gx.ValidationDefinition(
        name=VALIDATION_DEFINITION_NAME,
        data=batch_definition,
        suite=suite,
    )
    return context.validation_definitions.add_or_update(validation_definition)


def build_checkpoint(context, validation_definition):
    checkpoint = gx.Checkpoint(
        name=CHECKPOINT_NAME,
        validation_definitions=[validation_definition],
    )
    return context.checkpoints.add_or_update(checkpoint)


def main() -> int:
    create_demo_csv()
    context = get_or_create_context()
    datasource = get_or_create_datasource(context)
    asset = get_or_create_asset(datasource)
    batch_definition = get_or_create_batch_definition(asset)
    suite = build_suite(context)
    validation_definition = build_validation_definition(context, batch_definition, suite)
    checkpoint = build_checkpoint(context, validation_definition)

    dataframe = pd.read_csv(CSV_PATH)
    checkpoint_result = checkpoint.run(batch_parameters={"dataframe": dataframe})
    data_docs_info = context.build_data_docs()
    docs_index_path = normalize_index_path(extract_index_path(data_docs_info))

    payload = {
        "success": bool(getattr(checkpoint_result, "success", False)),
        "docs_index_path": str(docs_index_path),
        "docs_site_dir": str(docs_index_path.parent),
        "project_root": str(PROJECT_ROOT),
        "data_file": str(CSV_PATH),
        "suite_name": SUITE_NAME,
        "validation_definition_name": VALIDATION_DEFINITION_NAME,
        "checkpoint_name": CHECKPOINT_NAME,
        "summary": checkpoint_result.describe(),
    }
    write_result(payload)
    print(json.dumps(payload, indent=2))
    return 0 if payload["success"] else 1


if __name__ == "__main__":
    try:
        raise SystemExit(main())
    except Exception as exc:  # pragma: no cover - defensive logging path
        payload = {
            "success": False,
            "error": str(exc),
            "project_root": str(PROJECT_ROOT),
        }
        write_result(payload)
        print(json.dumps(payload, indent=2), file=sys.stderr)
        raise
