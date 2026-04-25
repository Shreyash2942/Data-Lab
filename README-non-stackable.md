# Data Lab Standalone Mode

This guide is the entry point for running Data Lab without Docker Compose stack labels.

In standalone mode, you run one container directly with `docker run` or the helper scripts under `helper/scripts/`. This is useful when you want a simpler local launch flow, direct control over container names, or cloned containers with remapped host ports.

## Start Here

- [Main README](README.md)
- [Standalone Run Guide](docs/STANDALONE-RUN.md)
- [Access Reference](docs/ACCESS-REFERENCE.md)
- [Helper Scripts Reference](helper/scripts/README.md)

## Quick Commands

Build locally:

```bash
docker build -t data-lab:latest .
```

Run on Linux or macOS:

```bash
NAME=datalab IMAGE=data-lab:latest ./helper/scripts/run-standalone.sh
```

Run on Windows PowerShell:

```powershell
powershell -ExecutionPolicy Bypass -File .\helper\scripts\run-standalone.ps1 -Name datalab -Image data-lab:latest
```

Show mapped service URLs:

```powershell
powershell -ExecutionPolicy Bypass -File .\helper\scripts\ui-services.ps1 -Name datalab -UiHost localhost
```

## What This Covers

- standalone launch workflows
- helper scripts for build, run, copy, and UI discovery
- database UI and pgAdmin access
- manual `docker run` fallback commands
- dynamic port guidance for copied containers

For the full walkthrough, use [docs/STANDALONE-RUN.md](docs/STANDALONE-RUN.md).
