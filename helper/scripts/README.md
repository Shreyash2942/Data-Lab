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
  NAME=datalab IMAGE=shreyash42/data-lab:latest ./helper/scripts/run-standalone.sh
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
  powershell -File .\helper\scripts\run-standalone.ps1 -Name datalab -Image shreyash42/data-lab:latest
  ```
- PowerShell build + run (build image, then run non-stackable container):
  ```powershell
  powershell -File .\helper\scripts\build-and-run.ps1 -Name datalab -Image data-lab:latest
  ```
- PowerShell copy container (asks new name and bind mounts, reuses source image):
  ```powershell
  powershell -File .\helper\scripts\copy-container.ps1 -SourceName datalab
  ```
- PowerShell UI links (dynamic mapped host ports):
  ```powershell
  powershell -File .\helper\scripts\ui-services.ps1 -Name datalab -UiHost localhost
  ```
- PowerShell DB access guide (dynamic ports + prompted credentials + IDE values):
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

- `run-standalone.sh` (bash): Stops/removes any existing container with the same name, then starts the Data Lab image detached with standard port bindings and workspace mounts. Env overrides: `NAME`, `IMAGE`, `EXTRA_PORTS`, `EXTRA_VOLUMES`.
- `run-standalone.ps1` (PowerShell): Same behavior/flags as the bash version (`-Name`, `-Image`, `-ExtraPorts`, `-ExtraVolumes`).
- `run-standalone-interactive.sh` (bash): Prompts for container name and any number of extra host-to-container bind mounts; default ports are always mapped. Uses `shreyash42/data-lab:latest` unless `IMAGE` is set. Pass `EXTRA_PORTS` if you want additional ports.
- `run-standalone-interactive.ps1` (PowerShell): Prompts for container name and any number of extra host-to-container bind mounts; default ports are always mapped. Uses `shreyash42/data-lab:latest` unless `-Image` is provided. Pass `-ExtraPorts` if you want additional ports. Uses the repo root (two levels up from `helper/scripts/`) for default mounts.
- `build-and-run.ps1` (PowerShell): Builds the image (unless `-SkipBuild`), then runs a non-stackable container with standard ports and default repo mounts. Supports `-ExtraPorts` and `-ExtraVolumes`, and validates host port conflicts before run.
- `copy-container.ps1` (PowerShell): Uses the image from an existing container (default `datalab`), asks for a new container name and bind mounts, and starts another non-stackable container. Default UI ports auto-shift to the next free host port when needed to avoid conflicts.
- `run-default.sh` (bash): Quick run with standard port bindings; accepts extra args after the image name.
- `run-default.ps1` (PowerShell): Quick run equivalent for Windows; first arg is container name, remaining args are passed to `docker run`.
- `ui-services.ps1` (PowerShell): Prints all UI URLs using Docker port mappings for the selected running container.
- `db-access-guide.ps1` (PowerShell): Prompts for DB usernames/passwords and prints exact browser + IDE connection values (PostgreSQL, MongoDB, Redis) using real mapped host ports.
- `start-pgadmin.ps1` (PowerShell): Starts an official `dpage/pgadmin4` container, preconfigures a server entry that points to the mapped PostgreSQL port of your target Data Lab container, and prints login details.

## Notes

- Default image: `data-lab:latest` (or the published `shreyash42/data-lab:latest`).
- Default ports published: 8080, 4040, 9090, 18080, 9092, 9870, 8088, 10000, 10001, 9002, 8082, 8083, 8084, 8181, 5432, 27017, 6379.
- Default mounts map repo folders (`datalabcontainer/app`, `datalabcontainer/runtime`, and all `stacks/*`) into `/home/datalab/...`.
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


