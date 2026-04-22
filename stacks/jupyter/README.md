# Jupyter Stack

This stack documents the embedded JupyterLab environment used for notebook-based exploration.

## Runtime Management

- Service module: `datalabcontainer/app/tech/jupyter/`
- Start: `datalab_app --start-jupyter`
- UI helper: `ui_services`

## Endpoints

- Inside container: `http://localhost:8888/lab?token=datalab`
- Outside host: resolved through `DATALAB_HOST_PORT_MAP`

## Runtime Data

- Notebooks: `~/runtime/jupyter/notebooks/`
- Starter notebook: `~/runtime/jupyter/notebooks/DataLab_Phase3_Quickstart.ipynb`

## Why This Stack Exists

- Give you a fast notebook workspace for ad hoc data engineering work.
- Make it easy to test PySpark logic before turning it into scripts or DAG tasks.
- Provide a friendly place for exploration, debugging, and one-off checks.

## Common Use Cases

- Explore data written by Spark, Hive, or lakehouse jobs.
- Prototype transformation logic before moving it into production scripts.
- Inspect quality outputs from Great Expectations or CDC demo data.

## How To Use In Data Lab

Start JupyterLab:

```bash
datalab_app --start-jupyter
```

Open the starter notebook:

```text
~/runtime/jupyter/notebooks/DataLab_Phase3_Quickstart.ipynb
```

Login token:

```text
datalab
```

## Notes

- JupyterLab is included in the single Data Lab image.
- It is intended for ad hoc analysis and PySpark exploration.
