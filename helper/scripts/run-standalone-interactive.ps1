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

# Image (no prompt; override via -Image)
if (-not $Image) { $Image = $DefaultImage }
Write-Host "Using image: $Image (override with -Image if needed)"

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
  "9092:9092", "9870:9870", "8088:8088", "10000:10000",
  "10001:10001", "9002:9002", "8082:8082", "8083:8083", "8084:8084", "8181:8181",
  "5432:5432", "27017:27017", "6379:6379"
)

# Default volumes (repo root is two levels up from this scripts folder)
$repoRoot = (Resolve-Path (Join-Path $PSScriptRoot "..\.."))
$datalabDir = Join-Path $repoRoot "datalabcontainer"
$stacksDir = Join-Path $repoRoot "stacks"
$defaultVolumes = @(
  "$datalabDir\app:/home/datalab/app",
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
  "$stacksDir\hudi:/home/datalab/hudi",
  "$stacksDir\iceberg:/home/datalab/iceberg",
  "$stacksDir\delta:/home/datalab/delta",
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

Write-Output "Container $Name started from $Image."
if ($collectedPorts.Count -gt 0) {
  Write-Output "Added port bindings: $($collectedPorts -join ', ')"
}
if ($collectedVolumes.Count -gt 0) {
  Write-Output "Mounted: $($collectedVolumes -join ', ')"
}
Write-Output "Enter with: docker exec -it -w / $Name bash"
