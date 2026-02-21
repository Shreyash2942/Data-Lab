# Data-Lab Structure

This repository uses a compact top-level layout:

- `datalabcontainer/`: container build/runtime orchestration.
- `helper/scripts/`: standalone helper scripts (single source of truth).
- `stacks/`: technology stack folders and examples.
- `docs/`: documentation and reference guides.
- `catalog/`: fast navigation indexes and run maps.

## Top-Level Tree

```text
Data-Lab/
|-- datalabcontainer/
|   |-- app/
|   |-- dev/
|   |-- runtime/
|   |-- docker-compose.yml
|   |-- docker-compose.image.yml
|   `-- .env.example
|-- helper/
|   `-- scripts/
|-- stacks/
|-- docs/
|-- catalog/
|-- README.md
`-- README-non-stackable.md
```

## Run Location

- Compose commands run from `datalabcontainer/`.
- Standalone scripts run from `helper/scripts/`.
