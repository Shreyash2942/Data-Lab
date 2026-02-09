Param(
  [string]$Name = "",
  [string]$Image = "",
  [string[]]$ExtraPorts = @(),
  [string[]]$ExtraVolumes = @()
)

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
  "10001:10001", "9002:9002"
)

# Default volumes (repo root is parent of this scripts folder)
$repoRoot = (Resolve-Path (Join-Path $PSScriptRoot ".."))
$defaultVolumes = @(
  "$repoRoot\app:/home/datalab/app",
  "$repoRoot\python:/home/datalab/python",
  "$repoRoot\spark:/home/datalab/spark",
  "$repoRoot\airflow:/home/datalab/airflow",
  "$repoRoot\dbt:/home/datalab/dbt",
  "$repoRoot\terraform:/home/datalab/terraform",
  "$repoRoot\scala:/home/datalab/scala",
  "$repoRoot\java:/home/datalab/java",
  "$repoRoot\hive:/home/datalab/hive",
  "$repoRoot\hadoop:/home/datalab/hadoop",
  "$repoRoot\kafka:/home/datalab/kafka",
  "$repoRoot\hudi:/home/datalab/hudi",
  "$repoRoot\iceberg:/home/datalab/iceberg",
  "$repoRoot\delta:/home/datalab/delta",
  "$repoRoot\runtime:/home/datalab/runtime"
)

docker stop $Name 2>$null | Out-Null
docker rm $Name 2>$null | Out-Null

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

Write-Output "Container $Name started from $Image."
if ($collectedPorts.Count -gt 0) {
  Write-Output "Added port bindings: $($collectedPorts -join ', ')"
}
if ($collectedVolumes.Count -gt 0) {
  Write-Output "Mounted: $($collectedVolumes -join ', ')"
}
Write-Output "Enter with: docker exec -it -w / $Name bash"
