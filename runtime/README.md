# Runtime State

This directory stores all logs, metadata, and working state produced by the monolithic container. Subfolders are created automatically for each stack (Airflow, Spark, Hadoop, Hive, Kafka, lakehouse formats, dbt, Terraform, etc.) so that code under the repo root stays clean while runtime data persists across container rebuilds.

Feel free to delete individual subfolders to reset a given stack; the helper scripts will recreate them when needed.
