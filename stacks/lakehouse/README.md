# Lakehouse Demo Assets

This folder groups demo assets used by `datalab_app --setup-lakehouse-demo`.

In the container image, this folder is copied to `/home/datalab/lakehouse`
and used by `datalab_app`, `services_demo.sh`, and Trino demo setup scripts.

Format-specific subfolders:

- `iceberg/`
- `delta/`
- `hudi/`

Each format folder can contain:

- `sql/` files for schema/table setup
- Spark SQL scripts where needed
- Optional demo scripts and README
