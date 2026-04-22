# Lakehouses Dev Config

This folder groups lakehouse service configuration and development assets.

Current layout:

- `trino/`: Trino lakehouse config template and smoke SQL
- `hive/`: Hive Metastore lakehouse config notes
- `superset/`: Superset lakehouse integration notes

Runtime and image wiring points here (not to per-engine folders).

Runtime convention used by scripts:

- Demo assets live under `stacks/lakehouse` in the repo.
- Image build copies these assets to `/home/datalab/lakehouse`.
- Scripts resolve this path via `LAKEHOUSE_STACK_ROOT` first, then fallback paths.
