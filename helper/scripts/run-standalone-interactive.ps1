Param(
  [string]$Name = "",
  [string]$Image = "",
  [string[]]$ExtraPorts = @(),
  [string[]]$ExtraVolumes = @()
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"
if ($PSVersionTable.PSVersion.Major -ge 7) {
  $PSNativeCommandUseErrorActionPreference = $false
}

Write-Host "Standalone container setup (press Enter to accept defaults)."
$DefaultImage = "shreyash42/data-lab:latest"

# Container name
$Name = if ($Name) { $Name } else { Read-Host "Container name [datalab]" }
if (-not $Name) { $Name = "datalab" }

# Image (locked to published latest)
if (-not $Image) { $Image = $DefaultImage }
if ($Image -ne $DefaultImage) {
  throw "This script is locked to image '$DefaultImage'. Remove custom image/tag overrides."
}
Write-Host "Using image: $DefaultImage"
Write-Host "Pulling latest image: $DefaultImage"
docker pull $DefaultImage
if ($LASTEXITCODE -ne 0) {
  throw "docker pull failed for '$DefaultImage'."
}

# Extra ports (optional via parameter only; defaults are always applied)
$collectedPorts = @()
if ($ExtraPorts.Count -gt 0) { $collectedPorts = $ExtraPorts }

# Collect extra volumes
$collectedVolumes = @()
if ($ExtraVolumes.Count -gt 0) {
  $collectedVolumes = $ExtraVolumes
} else {
  while ($true) {
    $hostPath = Read-Host "Host path to bind (blank to finish)"
    if (-not $hostPath) { break }
    if (-not (Test-Path $hostPath)) {
      Write-Error "Host path '$hostPath' does not exist."
      exit 1
    }
    $containerPath = Read-Host "Container path for this mount (e.g., /home/datalab/data)"
    if (-not $containerPath) {
      Write-Error "Container path is required when a host path is provided."
      exit 1
    }
    $collectedVolumes += "$hostPath`:$containerPath"
  }
}

# Default ports
$defaultPorts = @(
  "8080:8080", "4040:4040", "9090:9090", "18080:18080",
  "9092:9092", "9870:9870", "8088:8088", "9083:9083", "10000:10000",
  "10001:10001", "9002:9002", "8181:8181", "8083:8083", "8084:8084",
  "5432:5432", "27017:27017", "6379:6379"
)

# Default volumes (repo root is two levels up from this scripts folder)
$repoRoot = (Resolve-Path (Join-Path $PSScriptRoot "..\.."))
$datalabDir = Join-Path $repoRoot "datalabcontainer"
$stacksDir = Join-Path $repoRoot "stacks"
$defaultVolumes = @(
  "$datalabDir\app:/home/datalab/app",
  "$repoRoot\datalabconfig:/home/datalab/datalabconfig",
  "$stacksDir\python:/home/datalab/python",
  "$stacksDir\spark:/home/datalab/spark",
  "$stacksDir\airflow:/home/datalab/airflow",
  "$stacksDir\dbt:/home/datalab/dbt",
  "$stacksDir\terraform:/home/datalab/terraform",
  "$stacksDir\scala:/home/datalab/scala",
  "$stacksDir\java:/home/datalab/java",
  "$stacksDir\hive:/home/datalab/hive",
  "$stacksDir\hadoop:/home/datalab/hadoop",
  "$stacksDir\kafka:/home/datalab/kafka",
  "$stacksDir\mongodb:/home/datalab/mongodb",
  "$stacksDir\postgres:/home/datalab/postgres",
  "$stacksDir\redis:/home/datalab/redis",
  "$stacksDir\lakehouse:/home/datalab/lakehouse",
  "$datalabDir\runtime:/home/datalab/runtime"
)

$existingNames = @(docker container ls -a --format "{{.Names}}" 2>$null)
if ($existingNames -contains $Name) {
  docker rm -f $Name 2>$null | Out-Null
}

$portArgs = @()
foreach ($p in $defaultPorts) { $portArgs += @("-p", $p) }
foreach ($p in $collectedPorts) { $portArgs += @("-p", $p) }

$volumeArgs = @()
foreach ($v in $defaultVolumes) { $volumeArgs += @("-v", $v) }
foreach ($v in $collectedVolumes) { $volumeArgs += @("-v", $v) }

$dockerArgs = @(
  "run", "-d", "--name", $Name,
  "--user", "root",
  "--workdir", "/",
  "--label", "com.docker.compose.project=",
  "--label", "com.docker.compose.service=",
  "--label", "com.docker.compose.oneoff="
) + $portArgs + $volumeArgs + @($Image, "sleep", "infinity")

& docker @dockerArgs
if ($LASTEXITCODE -ne 0) {
  docker rm -f $Name 2>$null | Out-Null
  throw "docker run failed for '$Name'."
}

$bootstrapScript = @'
set -e
bootstrap_paths=(
  /home/datalab/runtime/spark/events
  /home/datalab/runtime/spark/warehouse
  /home/datalab/runtime/spark/logs
  /home/datalab/runtime/spark/pids
  /home/datalab/runtime/kafka/data
  /home/datalab/runtime/kafka/logs
  /home/datalab/runtime/kafka/pids
  /home/datalab/runtime/kafka/zookeeper-data
  /home/datalab/runtime/java
  /home/datalab/runtime/scala
)
mkdir -p "${bootstrap_paths[@]}"
touch /home/datalab/derby.log 2>/dev/null || true
for _ in $(seq 1 20); do
  id datalab >/dev/null 2>&1 && break
  sleep 1
done
if id datalab >/dev/null 2>&1; then
  chown -R datalab:datalab /home/datalab/runtime "${bootstrap_paths[@]}" /home/datalab/derby.log 2>/dev/null || true
  chmod -R u+rwX,go+rX /home/datalab/runtime "${bootstrap_paths[@]}" /home/datalab/derby.log 2>/dev/null || true
fi

for p in /home/datalab/app /home/datalab/datalabconfig; do
  [ -e "$p" ] || continue
  chown -R datalab:datalab "$p" 2>/dev/null || true
  chmod -R u+rwX,go+rX "$p" 2>/dev/null || true
done
'@
$bootstrapScript = $bootstrapScript -replace "`r", ""
docker exec $Name bash -lc $bootstrapScript 2>$null | Out-Null

Write-Output "Container $Name started from $Image."
if ($collectedPorts.Count -gt 0) {
  Write-Output "Added port bindings: $($collectedPorts -join ', ')"
}
if ($collectedVolumes.Count -gt 0) {
  Write-Output "Mounted: $($collectedVolumes -join ', ')"
}
Write-Output "Enter with: docker exec -it -w / $Name bash"
