Param(
  [string]$Name = "datalab",
  [string]$Image = "data-lab:latest",
  [string]$Context = "..",
  [string]$Dockerfile = "datalabcontainer/dev/base/Dockerfile",
  [string[]]$ExtraPorts = @(),
  [string[]]$ExtraVolumes = @(),
  [switch]$SkipBuild
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"
if ($PSVersionTable.PSVersion.Major -ge 7) {
  $PSNativeCommandUseErrorActionPreference = $false
}
$repoRoot = (Resolve-Path (Join-Path $PSScriptRoot "..\..")).Path

if ($Context -eq "..") {
  $Context = $repoRoot
}
if ($Dockerfile -eq "datalabcontainer/dev/base/Dockerfile") {
  $Dockerfile = (Join-Path $repoRoot "datalabcontainer/dev/base/Dockerfile")
}

function Get-HostPortFromMapping {
  Param([string]$Mapping)
  if ($Mapping -notmatch "^\d+:\d+$") {
    throw "Invalid port mapping '$Mapping'. Expected format 'host:container'."
  }
  return [int]($Mapping.Split(":")[0])
}

function Test-HostPortFree {
  Param([int]$Port)
  $dockerPorts = @(docker ps --format "{{.Ports}}" 2>$null)
  foreach ($line in $dockerPorts) {
    $matches = [regex]::Matches($line, ":(\d+)->")
    foreach ($m in $matches) {
      if ([int]$m.Groups[1].Value -eq $Port) {
        return $false
      }
    }
  }

  try {
    $inUse = Get-NetTCPConnection -LocalPort $Port -State Listen -ErrorAction SilentlyContinue
    if ($inUse) {
      return $false
    }
  } catch {
    # Fall back to socket bind probe below when cmdlet is unavailable.
  }

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
  "10001:10001", "9002:9002", "8082:8082", "8083:8083", "8084:8084", "8181:8181",
  "5432:5432", "27017:27017", "6379:6379"
)

$existingNames = @(docker container ls -a --format "{{.Names}}" 2>$null)
if ($existingNames -contains $Name) {
  docker rm -f $Name 2>$null | Out-Null
}

$allPorts = @($defaultPorts + $ExtraPorts)
$allHostPorts = @()
foreach ($mapping in $allPorts) {
  $allHostPorts += (Get-HostPortFromMapping -Mapping $mapping)
}
if (@($allHostPorts | Group-Object | Where-Object { $_.Count -gt 1 }).Count -gt 0) {
  $dupes = (@($allHostPorts | Group-Object | Where-Object { $_.Count -gt 1 } | ForEach-Object { $_.Name })) -join ", "
  throw "Duplicate host port mapping detected: $dupes"
}
foreach ($p in $allHostPorts) {
  if (-not (Test-HostPortFree -Port $p)) {
    throw "Host port $p is already in use. Stop the conflicting process/container or pass different -ExtraPorts."
  }
}

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

$portArgs = @()
foreach ($p in $defaultPorts) { $portArgs += @("-p", $p) }
foreach ($p in $ExtraPorts) { $portArgs += @("-p", $p) }

$hostPortMapEntries = @()
foreach ($mapping in $defaultPorts) {
  $parts = $mapping.Split(":")
  $hostPort = [int]$parts[0]
  $containerPort = [int]$parts[1]
  $hostPortMapEntries += "$containerPort=$hostPort"
}
$hostPortMap = $hostPortMapEntries -join ","

$volumeArgs = @()
foreach ($v in $defaultVolumes) { $volumeArgs += @("-v", $v) }
foreach ($v in $ExtraVolumes) { $volumeArgs += @("-v", $v) }

$dockerArgs = @(
  "run", "-d", "--name", $Name,
  "--user", "root",
  "--workdir", "/",
  "--label", "com.docker.compose.project=",
  "--label", "com.docker.compose.service=",
  "--label", "com.docker.compose.oneoff=",
  "-e", "DATALAB_UI_HOST=localhost",
  "-e", "DATALAB_HOST_PORT_MAP=$hostPortMap"
) + $portArgs + $volumeArgs + @($Image, "sleep", "infinity")

Write-Host "Starting container '$Name' from image '$Image'..."
& docker @dockerArgs
if ($LASTEXITCODE -ne 0) {
  throw "docker run failed."
}

$uiMapFile = "/home/datalab/runtime/ui-port-map.env"
$uiMapScript = @"
cat > $uiMapFile <<'EOF'
DATALAB_UI_HOST=localhost
DATALAB_HOST_PORT_MAP=$hostPortMap
EOF
chmod 644 $uiMapFile || true
"@
docker exec $Name sh -lc $uiMapScript 2>$null | Out-Null

Write-Output "Container $Name started from $Image."
Write-Output "Enter with: docker exec -it -w / $Name bash"
