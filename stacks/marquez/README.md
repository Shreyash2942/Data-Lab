# Marquez Stack

This stack documents the embedded Marquez lineage backend and UI.

## Runtime Management

- Service module: `datalabcontainer/app/tech/lineage/`
- Start lineage stack: `datalab_app --start-lineage`
- Run demo: `datalab_app --run-lineage-demo`

## Endpoints

- API inside container: `http://localhost:5000/api/v1/namespaces`
- UI inside container: `http://localhost:3000/`
- Outside host: resolved through `DATALAB_HOST_PORT_MAP`

## Runtime Data

- Logs: `~/runtime/lineage/logs/`
- Demo data: `~/runtime/lineage/demo/`

## Why This Stack Exists

- Show lineage between jobs and datasets instead of treating pipelines as black boxes.
- Make Spark job inputs and outputs easier to inspect.
- Help explain impact when a dataset or job changes.

## Common Use Cases

- Validate that a Spark job emitted OpenLineage events.
- Inspect lineage between bronze and silver demo datasets.
- Demonstrate lineage concepts in a teaching or review session.

## How To Use In Data Lab

Start the lineage services:

```bash
datalab_app --start-lineage
```

Emit the built-in demo job:

```bash
datalab_app --run-lineage-demo
```

Then open the Marquez UI from `ui_services` and inspect the `datalab` namespace.

## Notes

- OpenLineage events from Spark are sent to Marquez.
- Marquez is included in the final Data Lab image through multi-stage build copy.
