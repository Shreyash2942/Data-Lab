# Data Lab helper scripts

Launch the Data Lab container without Docker Compose. Run from the repo root; defaults mount the repo folders into `/home/datalab/...` and publish the standard service ports.

## Quick commands

- Pull the published image:
  ```bash
  docker pull shreyash42/data-lab:latest
  ```
- Pull before running (if you have not built locally):
  ```powershell
  docker pull shreyash42/data-lab:latest
  ```
- Bash (Linux/macOS) non-interactive:
  ```bash
  chmod +x scripts/run-standalone.sh
  NAME=datalab IMAGE=shreyash42/data-lab:latest ./scripts/run-standalone.sh
  ```
- Bash interactive (prompts for name and extra mounts; uses default image unless `IMAGE` is set; default ports auto-mapped; extra ports optional via env var):
  ```bash
  chmod +x scripts/run-standalone-interactive.sh
  ./scripts/run-standalone-interactive.sh
  ```
- PowerShell interactive (prompts for name and extra mounts; uses default image unless `-Image` is provided; default ports auto-mapped; extra ports optional via `-ExtraPorts`):
  ```powershell
  powershell -File .\scripts\run-standalone-interactive.ps1
  ```
- PowerShell non-interactive:
  ```powershell
  powershell -File .\scripts\run-standalone.ps1 -Name datalab -Image shreyash42/data-lab:latest
  ```
- PowerShell build + run (build image, then run non-stackable container):
  ```powershell
  powershell -File .\scripts\build-and-run.ps1 -Name datalab -Image data-lab:latest
  ```
- PowerShell copy container (asks new name and bind mounts, reuses source image):
  ```powershell
  powershell -File .\scripts\copy-container.ps1 -SourceName datalab
  ```
- Minimal "quick run" (bash):
  ```bash
  chmod +x scripts/run-default.sh
  ./scripts/run-default.sh datalab
  ```
- Minimal "quick run" (PowerShell):
  ```powershell
  powershell -File .\scripts\run-default.ps1 datalab
  ```

## Script details

- `run-standalone.sh` (bash): Stops/removes any existing container with the same name, then starts the Data Lab image detached with standard port bindings and workspace mounts. Env overrides: `NAME`, `IMAGE`, `EXTRA_PORTS`, `EXTRA_VOLUMES`.
- `run-standalone.ps1` (PowerShell): Same behavior/flags as the bash version (`-Name`, `-Image`, `-ExtraPorts`, `-ExtraVolumes`).
- `run-standalone-interactive.sh` (bash): Prompts for container name and any number of extra host-to-container bind mounts; default ports are always mapped. Uses `shreyash42/data-lab:latest` unless `IMAGE` is set. Pass `EXTRA_PORTS` if you want additional ports.
- `run-standalone-interactive.ps1` (PowerShell): Prompts for container name and any number of extra host-to-container bind mounts; default ports are always mapped. Uses `shreyash42/data-lab:latest` unless `-Image` is provided. Pass `-ExtraPorts` if you want additional ports. Uses the repo root (parent of `scripts/`) for default mounts.
- `build-and-run.ps1` (PowerShell): Builds the image (unless `-SkipBuild`), then runs a non-stackable container with standard ports and default repo mounts. Supports `-ExtraPorts` and `-ExtraVolumes`.
- `copy-container.ps1` (PowerShell): Uses the image from an existing container (default `datalab`), asks for a new container name and bind mounts, and starts another non-stackable container with default ports.
- `run-default.sh` (bash): Quick run with standard port bindings; accepts extra args after the image name.
- `run-default.ps1` (PowerShell): Quick run equivalent for Windows; first arg is container name, remaining args are passed to `docker run`.

## Notes

- Default image: `data-lab:latest` (or the published `shreyash42/data-lab:latest`).
- Default ports published: 8080, 4040, 9090, 18080, 9092, 9870, 8088, 10000, 10001, 9002.
- Default mounts map repo folders (app, python, spark, airflow, dbt, terraform, scala, java, hive, hadoop, kafka, hudi, iceberg, delta, runtime) into `/home/datalab/...`.
- On macOS/Linux: run the `chmod +x` commands once to make the bash scripts executable.

## Cross-machine script reliability

If scripts fail after cloning on another machine, renormalize once from repo root:

```powershell
git add --renormalize .
git status --short
```

Then commit the normalization result so future clones stay consistent:

```powershell
git commit -m "Normalize line endings for scripts"
```

This repo enforces line endings with `.gitattributes` (`*.sh` as LF, `*.ps1` as CRLF) and editor defaults with `.editorconfig`.
