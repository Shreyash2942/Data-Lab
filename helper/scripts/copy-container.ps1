Param(
  [string]$SourceName = "datalab",
  [string]$NewName = "",
  [string[]]$ExtraPorts = @(),
  [string]$UiHost = "localhost"
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"
if ($PSVersionTable.PSVersion.Major -ge 7) {
  $PSNativeCommandUseErrorActionPreference = $false
}
$repoRoot = (Resolve-Path (Join-Path $PSScriptRoot "..\..")).Path

function Test-ContainerExists {
  Param([string]$Name)
  $names = docker container ls -a --format "{{.Names}}"
  return ($names -contains $Name)
}

function Get-HostPortFromMapping {
  Param([string]$Mapping)
  if ($Mapping -notmatch "^\d+:\d+$") {
    throw "Invalid port mapping '$Mapping'. Expected format 'host:container'."
  }
  return [int]($Mapping.Split(":")[0])
}

function Get-ContainerPortFromMapping {
  Param([string]$Mapping)
  if ($Mapping -notmatch "^\d+:\d+$") {
    throw "Invalid port mapping '$Mapping'. Expected format 'host:container'."
  }
  return [int]($Mapping.Split(":")[1])
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

function Get-FreeHostPort {
  Param([int]$PreferredPort, [int[]]$ReservedPorts)
  $candidate = $PreferredPort
  while ($candidate -le 65535) {
    if (($ReservedPorts -notcontains $candidate) -and (Test-HostPortFree -Port $candidate)) {
      return $candidate
    }
    $candidate++
  }
  throw "Could not find a free host port for preferred base $PreferredPort."
}

if (-not $NewName) {
  $NewName = Read-Host "New container name"
}
if (-not $NewName) {
  throw "Container name is required."
}

$exists = docker container inspect $SourceName 2>$null
if ($LASTEXITCODE -ne 0) {
  throw "Source container '$SourceName' not found."
}

$image = (docker inspect -f "{{.Config.Image}}" $SourceName).Trim()
if (-not $image) {
  throw "Could not detect image from source container '$SourceName'."
}

Write-Host "Source container: $SourceName"
Write-Host "Using image: $image"

$defaultPorts = @(
  "8080:8080", "4040:4040", "9090:9090", "18080:18080",
  "9092:9092", "9870:9870", "8088:8088", "10000:10000",
  "10001:10001", "9002:9002", "8082:8082", "8083:8083", "8084:8084", "8181:8181",
  "5432:5432", "27017:27017", "6379:6379"
)

$resolvedDefaultPorts = @()
$reservedPorts = @()
foreach ($mapping in $defaultPorts) {
  $preferredHostPort = Get-HostPortFromMapping -Mapping $mapping
  $containerPort = Get-ContainerPortFromMapping -Mapping $mapping
  $resolvedHostPort = Get-FreeHostPort -PreferredPort $preferredHostPort -ReservedPorts $reservedPorts
  $reservedPorts += $resolvedHostPort
  $resolvedDefaultPorts += "$resolvedHostPort`:$containerPort"
}

$normalizedExtraPorts = @()
foreach ($mapping in $ExtraPorts) {
  $hostPort = Get-HostPortFromMapping -Mapping $mapping
  if ($reservedPorts -contains $hostPort) {
    throw "Extra host port $hostPort conflicts with a mapped default port. Choose a different -ExtraPorts value."
  }
  if (-not (Test-HostPortFree -Port $hostPort)) {
    throw "Extra host port $hostPort is already in use."
  }
  $reservedPorts += $hostPort
  $normalizedExtraPorts += $mapping
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
  "$stacksDir\delta:/home/datalab/delta"
)

$collectedVolumes = @()
while ($true) {
  $hostPath = Read-Host "Host path to bind (blank to finish)"
  if (-not $hostPath) { break }
  if (-not (Test-Path $hostPath)) {
    Write-Host "Path '$hostPath' does not exist. Try again."
    continue
  }

  $containerPath = Read-Host "Container path for this mount (e.g., /home/datalab/data)"
  if (-not $containerPath) {
    Write-Host "Container path is required. Try again."
    continue
  }

  $collectedVolumes += "$hostPath`:$containerPath"
}

while (Test-ContainerExists $NewName) {
  Write-Host "Container '$NewName' already exists."
  $choice = Read-Host "Choose: [R]emove existing, [N]ew name, [C]ancel"
  $choiceNormalized = if ($null -eq $choice) { "" } else { $choice.Trim().ToUpperInvariant() }
  switch ($choiceNormalized) {
    "R" {
      docker rm -f $NewName 2>$null | Out-Null
    }
    "N" {
      $candidate = Read-Host "Enter a different container name"
      if (-not $candidate) {
        Write-Host "Container name is required. Try again."
        continue
      }
      $NewName = $candidate.Trim()
    }
    "C" {
      throw "Canceled by user."
    }
    default {
      Write-Host "Invalid choice. Enter R, N, or C."
    }
  }
}

$runtimeCopiesRoot = Join-Path $datalabDir "runtime-copies"
$runtimeCopyDir = Join-Path $runtimeCopiesRoot $NewName
New-Item -ItemType Directory -Force -Path $runtimeCopyDir | Out-Null
$defaultVolumes += "${runtimeCopyDir}:/home/datalab/runtime"

$portArgs = @()
foreach ($p in $resolvedDefaultPorts) { $portArgs += @("-p", $p) }
foreach ($p in $normalizedExtraPorts) { $portArgs += @("-p", $p) }

$volumeArgs = @()
foreach ($v in $defaultVolumes) { $volumeArgs += @("-v", $v) }
foreach ($v in $collectedVolumes) { $volumeArgs += @("-v", $v) }

$hostPortMapEntries = @()
foreach ($mapping in $resolvedDefaultPorts) {
  $parts = $mapping.Split(":")
  $hostPort = [int]$parts[0]
  $containerPort = [int]$parts[1]
  $hostPortMapEntries += "$containerPort=$hostPort"
}
$hostPortMap = $hostPortMapEntries -join ","

$envArgs = @(
  "-e", "DATALAB_UI_HOST=$UiHost",
  "-e", "DATALAB_HOST_PORT_MAP=$hostPortMap"
)

$dockerArgs = @(
  "run", "-d", "--name", $NewName,
  "--user", "root",
  "--workdir", "/",
  "--label", "com.docker.compose.project=",
  "--label", "com.docker.compose.service=",
  "--label", "com.docker.compose.oneoff="
) + $portArgs + $volumeArgs + $envArgs + @($image, "sleep", "infinity")

Write-Host "Starting copied container '$NewName'..."
& docker @dockerArgs
if ($LASTEXITCODE -ne 0) {
  throw "docker run failed for '$NewName'."
}

$uiMapFile = "/home/datalab/runtime/ui-port-map.env"
$uiMapScript = @"
cat > $uiMapFile <<'EOF'
DATALAB_UI_HOST=$UiHost
DATALAB_HOST_PORT_MAP=$hostPortMap
EOF
chmod 644 $uiMapFile || true
"@
docker exec $NewName sh -lc $uiMapScript 2>$null | Out-Null

Write-Output "Container $NewName started from image $image."
Write-Output "Published ports:"
foreach ($p in $resolvedDefaultPorts) {
  Write-Output "  - $p"
}
if ($normalizedExtraPorts.Count -gt 0) {
  foreach ($p in $normalizedExtraPorts) {
    Write-Output "  - $p (extra)"
  }
}
if ($collectedVolumes.Count -gt 0) {
  Write-Output "Mounted: $($collectedVolumes -join ', ')"
}
Write-Output "Runtime mount: ${runtimeCopyDir}:/home/datalab/runtime"

$serviceMap = @{
  8080  = @{ Name = "Airflow";         Path = "/" }
  9090  = @{ Name = "Spark Master";    Path = "/" }
  18080 = @{ Name = "Spark History";   Path = "/" }
  4040  = @{ Name = "Spark App UI";    Path = "/" }
  9870  = @{ Name = "HDFS NameNode";   Path = "/" }
  8088  = @{ Name = "YARN ResourceMgr";Path = "/" }
  10001 = @{ Name = "HiveServer2 HTTP";Path = "/cliservice" }
  9002  = @{ Name = "Kafka UI";        Path = "/" }
  8082  = @{ Name = "Adminer UI";      Path = "/" }
  8083  = @{ Name = "Mongo Express UI";Path = "/" }
  8084  = @{ Name = "Redis Commander UI"; Path = "/" }
  8181  = @{ Name = "pgAdmin UI"; Path = "/" }
}

Write-Output "UI URLs (dynamic host ports):"
foreach ($mapping in $resolvedDefaultPorts) {
  $parts = $mapping.Split(":")
  $hostPort = [int]$parts[0]
  $containerPort = [int]$parts[1]
  if ($serviceMap.ContainsKey($containerPort)) {
    $entry = $serviceMap[$containerPort]
    Write-Output ("  - {0}: http://{1}:{2}{3}" -f $entry.Name, $UiHost, $hostPort, $entry.Path)
  }
}

Write-Output "Tip: powershell -ExecutionPolicy Bypass -File .\helper\scripts\ui-services.ps1 -Name $NewName -UiHost $UiHost"
Write-Output "Enter with: docker exec -it -w / $NewName bash"
