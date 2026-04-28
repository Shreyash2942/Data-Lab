# Data Lab helper scripts

Launch the Data Lab container without Docker Compose. Run from the repo root; defaults mount `datalabcontainer/` + `stacks/` folders into `/home/datalab/...` and publish the standard service ports.

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
  chmod +x helper/scripts/run-standalone.sh
  NAME=datalab ./helper/scripts/run-standalone.sh
  ```
- Bash interactive (prompts for name and extra mounts; uses default image unless `IMAGE` is set; default ports auto-mapped; extra ports optional via env var):
  ```bash
  chmod +x helper/scripts/run-standalone-interactive.sh
  ./helper/scripts/run-standalone-interactive.sh
  ```
- PowerShell interactive (prompts for name and extra mounts; uses default image unless `-Image` is provided; default ports auto-mapped; extra ports optional via `-ExtraPorts`):
  ```powershell
  powershell -File .\helper\scripts\run-standalone-interactive.ps1
  ```
- PowerShell non-interactive:
  ```powershell
  powershell -File .\helper\scripts\run-standalone.ps1 -Name datalab
  ```
- PowerShell build + run (build image, then run non-stackable container):
  ```powershell
  powershell -File .\helper\scripts\build-and-run.ps1 -Name datalab
  ```
- PowerShell copy container (asks new name and bind mounts, defaults to published image and pulls latest before run):
  ```powershell
  powershell -File .\helper\scripts\copy-container.ps1
  ```
- PowerShell data access guide (dynamic ports + prompted credentials + IDE values):
  ```powershell
  powershell -File .\helper\scripts\db-access-guide.ps1 -Name datalab -UiHost localhost
  ```
- PowerShell pgAdmin (official pgAdmin4 UI, separate container, auto-wired to Data Lab PostgreSQL):
  ```powershell
  powershell -File .\helper\scripts\start-pgadmin.ps1 -TargetContainer datalab -PgAdminPort 8181
  ```
- Minimal "quick run" (bash):
  ```bash
  chmod +x helper/scripts/run-default.sh
  ./helper/scripts/run-default.sh datalab
  ```
- Minimal "quick run" (PowerShell):
  ```powershell
  powershell -File .\helper\scripts\run-default.ps1 datalab
  ```

## Script details

- `run-standalone.sh` (bash): Stops/removes any existing container with the same name, then starts the Data Lab image detached with standard port bindings and workspace mounts. Allows only `data-lab:latest` or `shreyash42/data-lab:latest`; the Docker Hub tag is pulled before run. Env overrides: `NAME`, `IMAGE`, `EXTRA_PORTS`, `EXTRA_VOLUMES`.
- `run-standalone.ps1` (PowerShell): Same behavior/flags as the bash version (`-Name`, `-Image`, `-ExtraPorts`, `-ExtraVolumes`). Allows only `data-lab:latest` or `shreyash42/data-lab:latest`; the Docker Hub tag is pulled before run. Lakehouse/UI ports are included by default; `-IncludeLakehousePorts` is retained only for backward compatibility.
- `run-standalone-interactive.sh` (bash): Prompts for container name and any number of extra host-to-container bind mounts; default ports are always mapped. Allows only `data-lab:latest` or `shreyash42/data-lab:latest`; the Docker Hub tag is pulled before run. Pass `EXTRA_PORTS` if you want additional ports.
- `run-standalone-interactive.ps1` (PowerShell): Prompts for container name and any number of extra host-to-container bind mounts; default ports are always mapped. Allows only `data-lab:latest` or `shreyash42/data-lab:latest`; the Docker Hub tag is pulled before run. Pass `-ExtraPorts` if you want additional ports. Uses the repo root (two levels up from `helper/scripts/`) for default mounts.
- `build-and-run.ps1` (PowerShell): Builds the image (unless `-SkipBuild`), then runs a non-stackable container with standard ports and default repo mounts. Supports `-ExtraPorts` and `-ExtraVolumes`, validates host port conflicts before run, and now includes the lakehouse/UI ports by default.
- `copy-container.ps1` (PowerShell): Allows only `data-lab:latest` or `shreyash42/data-lab:latest`, and blocks image IDs/digests so copied containers do not start from dangling images. The Docker Hub tag is pulled before run unless `-SkipPull` is used for local testing. Full platform ports (core + lakehouse) auto-shift to the next free host port when needed to avoid conflicts.
- `run-default.sh` (bash): Quick run with the standard port set, including Superset/Trino/MinIO host ports; allows only `data-lab:latest` or `shreyash42/data-lab:latest`.
- `run-default.ps1` (PowerShell): Quick run equivalent for Windows with the same default port set; first arg is container name; allows only `data-lab:latest` or `shreyash42/data-lab:latest`.
- `db-access-guide.ps1` (PowerShell): Prompts for database and MinIO credentials, then prints exact browser + IDE/SDK connection values using real mapped host ports.
- `start-pgadmin.ps1` (PowerShell): Starts an official `dpage/pgadmin4` container, preconfigures a server entry that points to the mapped PostgreSQL port of your target Data Lab container, and prints login details.

## copy-container.ps1 guide

Use this when you want another Data Lab container from the same image, with auto-resolved host ports to avoid collisions.

### Basic usage

```powershell
powershell -File .\helper\scripts\copy-container.ps1
```

If PowerShell blocks script execution on your machine, use:

```powershell
powershell -ExecutionPolicy Bypass -File .\helper\scripts\copy-container.ps1
```

The script will prompt for:

- New container name
- Optional additional bind mounts (`host_path:container_path`)

### Common examp

### les

- Use default behavior (published image + auto-pull) and set name directly:

  ```powershell
  powershell -File .\helper\scripts\copy-container.ps1 -NewName datalab-copy
  ```
- Pull and use a specific image tag:

  ```powershell
  powershell -File .\helper\scripts\copy-container.ps1 -NewName datalab-copy -Image shreyash42/data-lab:latest
  ```
- Force a fresh pull even if the image exists locally:

  ```powershell
  powershell -File .\helper\scripts\copy-container.ps1 -NewName datalab-copy -Image shreyash42/data-lab:latest -ForcePull
  ```
- Use a locally rebuilt `shreyash42/data-lab:latest` without pulling Docker Hub:

  ```powershell
  powershell -File .\helper\scripts\copy-container.ps1 -NewName datalab-copy -SkipPull
  ```
- Reuse image from an existing local container:

  ```powershell
  powershell -File .\helper\scripts\copy-container.ps1 -UseSourceImage -SourceName datalab -NewName datalab-copy
  ```
- Bind this repo's project folders into the new container:

  ```powershell
  powershell -File .\helper\scripts\copy-container.ps1 -NewName datalab-copy -BindProjectFiles
  ```
- Add extra port mappings and custom UI host:

  ```powershell
  powershell -File .\helper\scripts\copy-container.ps1 -NewName datalab-copy -ExtraPorts 5555:5555,5601:5601 -UiHost localhost
  ```

### Parameters

- `-NewName <string>`: New container name. If omitted, prompted interactively.
- `-Image <repo/image:tag>`: Allowed values are `data-lab:latest` and `shreyash42/data-lab:latest`. Image IDs, digests, and other tags are blocked.
- `-UseSourceImage`: Use the image from an existing container instead of pulling `-Image`.
- `-ForcePull`: Force pull from Docker Hub before run (ignored when `-UseSourceImage` is set).
- `-SkipPull`: Use the local `shreyash42/data-lab:latest` tag without pulling Docker Hub first. Use this after a local rebuild before you push the image.
- `-SourceName <string>`: Source container name used with `-UseSourceImage`. Default: `datalab`.
- `-ExtraPorts <host:container,...>`: Additional published ports in `host:container` format.
- `-UiHost <string>`: Hostname used when printing UI URLs. Default: `localhost`.
- `-BindProjectFiles`: Mount repo folders (`datalabcontainer/app` + `stacks/*`) into `/home/datalab/...`.
- `-ExcludeLakehousePorts`: Optional. Skip default lakehouse port mappings (8090, 8091, 9004, 9005).

### What you get after start

- Container starts detached with dynamic default port mappings (first free host ports).
- Script prints published ports and UI URLs.
- Enter shell with:
  ```powershell
  docker exec -it -w / <new_container_name> bash
  ```

## Notes

- Default image: `shreyash42/data-lab:latest`. Local development can explicitly use `data-lab:latest`.
- Default ports published (dynamic host mapping): 8080, 4040, 9090, 18080, 9092, 9870, 8088, 9083, 10000, 10001, 9002, 8181, 8083, 8084, 8085, 8086, 8888, 8891, 5000, 3000, 9095, 3001, 5432, 27017, 6379, 8090, 8091, 9004, 9005.
- Default mounts map repo folders (`datalabcontainer/app`, `datalabconfig/`, `datalabcontainer/runtime`, and all `stacks/*`) into `/home/datalab/...`.
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

Script source of truth: `helper/scripts/*`.

## In-container config command

Data Lab now also ships a separate runtime tuning command inside the container:

```bash
datalab_config show
datalab_config detect
datalab_config recommend
datalab_config apply balanced
```

This command lives under the repo-root `datalabconfig/` folder and writes
runtime overrides to `/home/datalab/runtime/config/datalab-overrides.env`.
