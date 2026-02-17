Param(
  [string]$Name = "datalab",
  [string]$Image = "data-lab:latest",
  [string]$Context = ".",
  [string]$Dockerfile = "dev/base/Dockerfile",
  [string[]]$ExtraPorts = @(),
  [string[]]$ExtraVolumes = @(),
  [switch]$SkipBuild
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

function Get-HostPortFromMapping {
  Param([string]$Mapping)
  if ($Mapping -notmatch "^\d+:\d+$") {
    throw "Invalid port mapping '$Mapping'. Expected format 'host:container'."
  }
  return [int]($Mapping.Split(":")[0])
}

function Test-HostPortFree {
  Param([int]$Port)
  $listener = $null
  try {
    $listener = [System.Net.Sockets.TcpListener]::new([System.Net.IPAddress]::Loopback, $Port)
    $listener.Start()
    return $true
  } catch {
    return $false
  } finally {
    if ($null -ne $listener) {
      $listener.Stop()
    }
  }
}

# Build the image unless explicitly skipped.
if (-not $SkipBuild) {
  Write-Host "Building image '$Image' from '$Dockerfile'..."
  docker build -t $Image -f $Dockerfile $Context
  if ($LASTEXITCODE -ne 0) {
    throw "docker build failed."
  }
}

$defaultPorts = @(
  "8080:8080", "4040:4040", "9090:9090", "18080:18080",
  "9092:9092", "9870:9870", "8088:8088", "10000:10000",
  "10001:10001", "9002:9002"
)

docker stop $Name 2>$null | Out-Null
docker rm $Name 2>$null | Out-Null

$allPorts = @($defaultPorts + $ExtraPorts)
$allHostPorts = @()
foreach ($mapping in $allPorts) {
  $allHostPorts += (Get-HostPortFromMapping -Mapping $mapping)
}
if (($allHostPorts | Group-Object | Where-Object { $_.Count -gt 1 }).Count -gt 0) {
  $dupes = ($allHostPorts | Group-Object | Where-Object { $_.Count -gt 1 } | ForEach-Object { $_.Name }) -join ", "
  throw "Duplicate host port mapping detected: $dupes"
}
foreach ($p in $allHostPorts) {
  if (-not (Test-HostPortFree -Port $p)) {
    throw "Host port $p is already in use. Stop the conflicting process/container or pass different -ExtraPorts."
  }
}

$repoRoot = (Resolve-Path (Join-Path $PSScriptRoot "..")).Path
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

$portArgs = @()
foreach ($p in $defaultPorts) { $portArgs += @("-p", $p) }
foreach ($p in $ExtraPorts) { $portArgs += @("-p", $p) }

$volumeArgs = @()
foreach ($v in $defaultVolumes) { $volumeArgs += @("-v", $v) }
foreach ($v in $ExtraVolumes) { $volumeArgs += @("-v", $v) }

$dockerArgs = @(
  "run", "-d", "--name", $Name,
  "--user", "root",
  "--workdir", "/",
  "--label", "com.docker.compose.project=",
  "--label", "com.docker.compose.service=",
  "--label", "com.docker.compose.oneoff="
) + $portArgs + $volumeArgs + @($Image, "sleep", "infinity")

Write-Host "Starting container '$Name' from image '$Image'..."
& docker @dockerArgs
if ($LASTEXITCODE -ne 0) {
  throw "docker run failed."
}

Write-Output "Container $Name started from $Image."
Write-Output "Enter with: docker exec -it -w / $Name bash"
