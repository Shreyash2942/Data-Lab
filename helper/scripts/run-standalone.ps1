Param(
  [string]$Name = "datalab",
  [string]$Image = "shreyash42/data-lab:latest",
  [string]$ExtraPorts = "",
  [string]$ExtraVolumes = "",
  [switch]$IncludeLakehousePorts
)

# Create a non-stackable container with ports and host mounts for the workspace.
if ($PSVersionTable.PSVersion.Major -ge 7) {
  $PSNativeCommandUseErrorActionPreference = $false
}
$repoRoot = (Resolve-Path (Join-Path $PSScriptRoot "..\..")).Path
$datalabDir = Join-Path $repoRoot "datalabcontainer"
$stacksDir = Join-Path $repoRoot "stacks"

$fixedImage = "shreyash42/data-lab:latest"
if ($Image -ne $fixedImage) {
  throw "This script is locked to image '$fixedImage'. Remove custom image/tag overrides."
}

Write-Host "Pulling latest image: $fixedImage"
docker pull $fixedImage
if ($LASTEXITCODE -ne 0) {
  throw "docker pull failed for '$fixedImage'."
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

$existingNames = @(docker container ls -a --format "{{.Names}}" 2>$null)
if ($existingNames -contains $Name) {
  docker rm -f $Name 2>$null | Out-Null
}

$defaultPortMappings = @(
  "8080:8080", "4040:4040", "9090:9090", "18080:18080",
  "9092:9092", "9870:9870", "8088:8088", "9083:9083", "10000:10000",
  "10001:10001", "9002:9002", "8181:8181", "8083:8083", "8084:8084", "8085:8085", "8086:8086",
  "8888:8888", "8891:8891", "5000:5000", "3000:3000", "9095:9095", "3001:3001",
  "5432:5432", "27017:27017", "6379:6379",
  "8090:8090", "8091:8091", "9004:9004", "9005:9005"
)
# Lakehouse ports are part of the default published set. Keep the switch for
# backward compatibility with older invocations that passed it explicitly.

$resolvedDefaultPorts = @()
$reservedPorts = @()
foreach ($mapping in $defaultPortMappings) {
  $preferredHostPort = Get-HostPortFromMapping -Mapping $mapping
  $containerPort = Get-ContainerPortFromMapping -Mapping $mapping
  $resolvedHostPort = Get-FreeHostPort -PreferredPort $preferredHostPort -ReservedPorts $reservedPorts
  $reservedPorts += $resolvedHostPort
  $resolvedDefaultPorts += "$resolvedHostPort`:$containerPort"
}

$normalizedExtraPorts = @()
if ($ExtraPorts) {
  foreach ($mapping in ($ExtraPorts -split "[,\s]+" | Where-Object { $_ })) {
    $hostPort = Get-HostPortFromMapping -Mapping $mapping
    if ($reservedPorts -contains $hostPort) {
      throw "Extra host port $hostPort conflicts with existing mapped ports."
    }
    if (-not (Test-HostPortFree -Port $hostPort)) {
      throw "Extra host port $hostPort is already in use."
    }
    $reservedPorts += $hostPort
    $normalizedExtraPorts += $mapping
  }
}

$hostPortMapEntries = @()
foreach ($mapping in $resolvedDefaultPorts) {
  $parts = $mapping.Split(":")
  $hostPort = [int]$parts[0]
  $containerPort = [int]$parts[1]
  $hostPortMapEntries += "$containerPort=$hostPort"
}
$hostPortMap = $hostPortMapEntries -join ","

$portArgs = @()
foreach ($mapping in $resolvedDefaultPorts) { $portArgs += @("-p", $mapping) }
foreach ($mapping in $normalizedExtraPorts) { $portArgs += @("-p", $mapping) }

docker run -d --name $Name `
  --user root `
  --workdir / `
  --label com.docker.compose.project= `
  --label com.docker.compose.service= `
  --label com.docker.compose.oneoff= `
  -e CONTAINER_NAME="$Name" `
  -e DATALAB_UI_HOST=localhost `
  -e DATALAB_HOST_PORT_MAP="$hostPortMap" `
  $portArgs `
  -v ${datalabDir}\app:/home/datalab/app `
  -v ${repoRoot}\datalabconfig:/home/datalab/datalabconfig `
  -v ${stacksDir}\python:/home/datalab/python `
  -v ${stacksDir}\spark:/home/datalab/spark `
  -v ${stacksDir}\airflow:/home/datalab/airflow `
  -v ${stacksDir}\dbt:/home/datalab/dbt `
  -v ${stacksDir}\terraform:/home/datalab/terraform `
  -v ${stacksDir}\scala:/home/datalab/scala `
  -v ${stacksDir}\java:/home/datalab/java `
  -v ${stacksDir}\hive:/home/datalab/hive `
  -v ${stacksDir}\hadoop:/home/datalab/hadoop `
  -v ${stacksDir}\kafka:/home/datalab/kafka `
  -v ${stacksDir}\kafka_connect:/home/datalab/kafka_connect `
  -v ${stacksDir}\mongodb:/home/datalab/mongodb `
  -v ${stacksDir}\minio:/home/datalab/minio `
  -v ${stacksDir}\marquez:/home/datalab/marquez `
  -v ${stacksDir}\postgres:/home/datalab/postgres `
  -v ${stacksDir}\prometheus:/home/datalab/prometheus `
  -v ${stacksDir}\redis:/home/datalab/redis `
  -v ${stacksDir}\schema_registry:/home/datalab/schema_registry `
  -v ${stacksDir}\lakehouse:/home/datalab/lakehouse `
  -v ${stacksDir}\grafana:/home/datalab/grafana `
  -v ${stacksDir}\great_expectations:/home/datalab/great_expectations `
  -v ${stacksDir}\jupyter:/home/datalab/jupyter `
  -v ${stacksDir}\superset:/home/datalab/superset `
  -v ${stacksDir}\trino:/home/datalab/trino `
  -v ${datalabDir}\runtime:/home/datalab/runtime `
  $ExtraVolumes `
  $Image `
  sleep infinity

$uiMapFile = "/home/datalab/runtime/ui-port-map.env"
$uiMapScript = @"
cat > $uiMapFile <<'EOF'
DATALAB_UI_HOST=localhost
DATALAB_HOST_PORT_MAP=$hostPortMap
EOF
chmod 644 $uiMapFile || true
"@
$uiMapScript = $uiMapScript -replace "`r", ""
docker exec $Name sh -lc $uiMapScript 2>$null | Out-Null

$bootstrapScript = @'
set -e
# New container should start from a clean Kafka metadata state.
rm -rf /home/datalab/runtime/kafka/data/* /home/datalab/runtime/kafka/zookeeper-data/* 2>/dev/null || true
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

# Best-effort ownership fix for mounted Data Lab paths so copied/host-bound
# files are usable as the datalab user.
owned_paths=(
  /home/datalab/app
  /home/datalab/datalabconfig
  /home/datalab/airflow
  /home/datalab/dbt
  /home/datalab/lakehouse
  /home/datalab/hadoop
  /home/datalab/hive
  /home/datalab/java
  /home/datalab/kafka
  /home/datalab/kafka_connect
  /home/datalab/mongodb
  /home/datalab/minio
  /home/datalab/marquez
  /home/datalab/postgres
  /home/datalab/prometheus
  /home/datalab/python
  /home/datalab/redis
  /home/datalab/schema_registry
  /home/datalab/runtime
  /home/datalab/scala
  /home/datalab/spark
  /home/datalab/terraform
  /home/datalab/grafana
  /home/datalab/great_expectations
  /home/datalab/jupyter
  /home/datalab/superset
  /home/datalab/trino
)
for p in "${owned_paths[@]}"; do
  [ -e "$p" ] || continue
  chown -R datalab:datalab "$p" 2>/dev/null || true
  chmod -R u+rwX,go+rX "$p" 2>/dev/null || true
done
'@
$bootstrapScript = $bootstrapScript -replace "`r", ""
docker exec $Name bash -lc $bootstrapScript 2>$null | Out-Null

Write-Output "Container $Name started from $Image."
Write-Output "Published ports:"
foreach ($p in $resolvedDefaultPorts) {
  Write-Output "  - $p"
}
if ($normalizedExtraPorts.Count -gt 0) {
  foreach ($p in $normalizedExtraPorts) {
    Write-Output "  - $p (extra)"
  }
}
Write-Output "Enter with: docker exec -it -w / $Name bash"
