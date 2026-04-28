Param(
  [string]$SourceName = "datalab",
  [string]$NewName = "",
  [string]$Image = "",
  [switch]$UseSourceImage,
  [switch]$ForcePull,
  [switch]$SkipPull,
  [string[]]$ExtraPorts = @(),
  [string]$UiHost = "localhost",
  [switch]$BindProjectFiles,
  [switch]$IncludeLakehousePorts,
  [switch]$ExcludeLakehousePorts,
  [string]$DefaultProjectHostPath = "",
  [string]$DefaultProjectContainerPath = "/home/datalab/project",
  [switch]$SkipDefaultProjectMount,
  [switch]$NoPromptVolumes
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"
if ($PSVersionTable.PSVersion.Major -ge 7) {
  $PSNativeCommandUseErrorActionPreference = $false
}
$repoRoot = (Resolve-Path (Join-Path $PSScriptRoot "..\..")).Path
$lineEndingFixScript = Join-Path $repoRoot "helper\scripts\fix-line-endings.ps1"

function Test-ContainerExists {
  Param([string]$Name)
  $names = docker container ls -a --format "{{.Names}}"
  return ($names -contains $Name)
}

function Test-ImageExists {
  Param([string]$ImageRef)
  docker image inspect $ImageRef 1>$null 2>$null
  return ($LASTEXITCODE -eq 0)
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

function Invoke-LinuxLineEndingFix {
  Param([string]$RootPath)
  if (-not (Test-Path $lineEndingFixScript)) {
    Write-Warning "Line-ending fixer not found at '$lineEndingFixScript'. Skipping normalization."
    return
  }

  Write-Host "Normalizing LF line endings for Linux scripts under '$RootPath'..."
  & powershell -ExecutionPolicy Bypass -File $lineEndingFixScript -Root $RootPath
  if ($LASTEXITCODE -ne 0) {
    throw "Failed to normalize line endings at '$RootPath'."
  }
}

function Get-SafeVolumeSuffix {
  Param([string]$Name)
  $safe = ($Name -replace "[^a-zA-Z0-9_.-]", "-").ToLowerInvariant()
  if (-not $safe) {
    $safe = "default"
  }
  return $safe
}

function Resolve-ContainerMountPath {
  Param(
    [string]$InputPath,
    [string]$DefaultRoot = "/home/datalab"
  )

  $normalized = if ($null -eq $InputPath) { "" } else { [string]$InputPath }
  $normalized = $normalized.Trim()
  if (-not $normalized) {
    return ""
  }

  $normalized = $normalized.Replace("\", "/")

  if ($normalized.StartsWith("~/")) {
    $normalized = "$DefaultRoot/" + $normalized.Substring(2)
  } elseif (-not $normalized.StartsWith("/")) {
    $normalized = "$DefaultRoot/" + ($normalized.TrimStart(".","/"))
  }

  return ($normalized -replace "/{2,}", "/")
}

function Invoke-ContainerShellScript {
  Param(
    [string]$ContainerName,
    [string]$ScriptText,
    [string]$Shell = "bash",
    [string]$RemotePath = "/tmp/datalab-copy-bootstrap.sh"
  )

  $execCommand = "cat > '$RemotePath' && (sed -i 's/\r$//' '$RemotePath' 2>/dev/null || true) && $Shell '$RemotePath'"
  $ScriptText | docker exec -i $ContainerName $Shell -lc $execCommand 2>$null | Out-Null
  if ($LASTEXITCODE -ne 0) {
    throw "Failed to run bootstrap script '$RemotePath' in container '$ContainerName'."
  }
}

if (-not $NewName) {
  $NewName = Read-Host "New container name"
}
if (-not $NewName) {
  throw "Container name is required."
}

$localDefaultImage = "data-lab:latest"
$publishedDefaultImage = "shreyash42/data-lab:latest"
$allowedImages = @($localDefaultImage, $publishedDefaultImage)
$resolvedImage = $Image
if ($ForcePull -and $SkipPull) {
  throw "Use either -ForcePull or -SkipPull, not both."
}
if ($UseSourceImage) {
  $exists = docker container inspect $SourceName 2>$null
  if ($LASTEXITCODE -ne 0) {
    throw "Source container '$SourceName' not found."
  }

  $resolvedImage = (docker inspect -f "{{.Config.Image}}" $SourceName).Trim()
  if (-not $resolvedImage) {
    throw "Could not detect image from source container '$SourceName'."
  }
  if ($allowedImages -notcontains $resolvedImage) {
    throw "Source container '$SourceName' is using '$resolvedImage'. Use only '$localDefaultImage' or '$publishedDefaultImage'."
  }
  $sourceImageId = (docker inspect -f "{{.Image}}" $SourceName).Trim()
  $namedImageId = (docker image inspect $resolvedImage --format "{{.Id}}" 2>$null).Trim()
  if (-not $namedImageId -or $sourceImageId -ne $namedImageId) {
    throw "Source container '$SourceName' is not using the current '$resolvedImage' tag. Recreate it from a named image first."
  }
  Write-Host "Source container: $SourceName"
  Write-Host "Using source image: $resolvedImage"
} else {
  if (-not $resolvedImage) {
    $resolvedImage = $publishedDefaultImage
    Write-Host "Using published image by default: $resolvedImage"
  }
  if ($allowedImages -notcontains $resolvedImage) {
    throw "Use only '$localDefaultImage' or '$publishedDefaultImage'. Image IDs, digests, and other tags are blocked."
  }
}

if ($SkipPull) {
  if (-not (Test-ImageExists -ImageRef $resolvedImage)) {
    throw "Image '$resolvedImage' is not available locally. Build it first or remove -SkipPull."
  }
  Write-Host "Using local image without pull: $resolvedImage"
} elseif ($resolvedImage -eq $publishedDefaultImage) {
  Write-Host "Pulling image: $resolvedImage"
  docker pull $resolvedImage
  if ($LASTEXITCODE -ne 0) {
    throw "docker pull failed for image '$resolvedImage'."
  }
  Write-Host "Using pulled image: $resolvedImage"
} elseif (-not (Test-ImageExists -ImageRef $resolvedImage)) {
  throw "Image '$resolvedImage' is not available locally. Build it first or use '$publishedDefaultImage'."
} else {
  Write-Host "Using local named image: $resolvedImage"
}

$defaultPorts = @(
  "8080:8080", "4040:4040", "9090:9090", "18080:18080",
  "9092:9092", "9870:9870", "8088:8088", "9083:9083", "10000:10000",
  "10001:10001", "9002:9002", "8181:8181", "8083:8083", "8084:8084", "8085:8085", "8086:8086",
  "8888:8888", "8891:8891", "5000:5000", "3000:3000", "9095:9095", "3001:3001",
  "5432:5432", "27017:27017", "6379:6379"
)

# Include lakehouse/analytics ports by default so copied containers expose the
# full platform with conflict-free dynamic host mappings.
$includeLakehouseByDefault = $true
if ($ExcludeLakehousePorts -and -not $IncludeLakehousePorts) {
  $includeLakehouseByDefault = $false
}
if ($includeLakehouseByDefault) {
  $defaultPorts += @("8090:8090", "8091:8091", "9004:9004", "9005:9005")
}

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
$defaultVolumes = @()
if ($BindProjectFiles) {
  Invoke-LinuxLineEndingFix -RootPath $datalabDir
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
    "$stacksDir\kafka_connect:/home/datalab/kafka_connect",
    "$stacksDir\mongodb:/home/datalab/mongodb",
    "$stacksDir\minio:/home/datalab/minio",
    "$stacksDir\marquez:/home/datalab/marquez",
    "$stacksDir\postgres:/home/datalab/postgres",
    "$stacksDir\prometheus:/home/datalab/prometheus",
    "$stacksDir\redis:/home/datalab/redis",
    "$stacksDir\schema_registry:/home/datalab/schema_registry",
    "$stacksDir\lakehouse:/home/datalab/lakehouse",
    "$stacksDir\grafana:/home/datalab/grafana",
    "$stacksDir\great_expectations:/home/datalab/great_expectations",
    "$stacksDir\jupyter:/home/datalab/jupyter",
    "$stacksDir\superset:/home/datalab/superset",
    "$stacksDir\trino:/home/datalab/trino"
  )
}

if (-not $SkipDefaultProjectMount -and $DefaultProjectHostPath) {
  if (Test-Path $DefaultProjectHostPath) {
    $defaultVolumes += "$DefaultProjectHostPath`:$DefaultProjectContainerPath"
    Write-Host "Auto-mounted project path: $DefaultProjectHostPath -> $DefaultProjectContainerPath"
  } else {
    Write-Warning "Default project path '$DefaultProjectHostPath' was not found. Skipping auto-mount."
  }
}

$collectedVolumes = @()
if (-not $NoPromptVolumes) {
  $defaultContainerMountRoot = "/home/datalab"
  while ($true) {
    $hostPath = Read-Host "Host path to bind (blank to finish)"
    if (-not $hostPath) { break }
    if (-not (Test-Path $hostPath)) {
      Write-Host "Path '$hostPath' does not exist. Try again."
      continue
    }

    $containerPathInput = Read-Host "Container path/name for this mount (relative paths go under $defaultContainerMountRoot)"
    if (-not $containerPathInput) {
      Write-Host "Container path is required. Try again."
      continue
    }

    $containerPath = Resolve-ContainerMountPath -InputPath $containerPathInput -DefaultRoot $defaultContainerMountRoot
    if (-not $containerPath) {
      Write-Host "Container path is required. Try again."
      continue
    }

    Write-Host "Using container path: $containerPath"

    $collectedVolumes += "$hostPath`:$containerPath"
  }
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

$runtimeVolumeSuffix = Get-SafeVolumeSuffix -Name $NewName
$runtimeVolumeName = "datalab-runtime-$runtimeVolumeSuffix"
$existingVolumes = @(docker volume ls --format "{{.Name}}" 2>$null)
if ($existingVolumes -contains $runtimeVolumeName) {
  docker volume rm $runtimeVolumeName 1>$null 2>$null
}
docker volume create $runtimeVolumeName 1>$null | Out-Null
$defaultVolumes += "${runtimeVolumeName}:/home/datalab/runtime"

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

$airflowDagsFolder = "/home/datalab/airflow/dags"
if (-not $SkipDefaultProjectMount -and $DefaultProjectHostPath) {
  $projectAirflowHostPath = Join-Path $DefaultProjectHostPath "Airflow\dags"
  if (Test-Path $projectAirflowHostPath) {
    $airflowDagsFolder = (Resolve-ContainerMountPath -InputPath "$DefaultProjectContainerPath/Airflow/dags" -DefaultRoot "/home/datalab")
  }
}

$envArgs = @(
  "-e", "CONTAINER_NAME=$NewName",
  "-e", "DATALAB_UI_HOST=$UiHost",
  "-e", "DATALAB_HOST_PORT_MAP=$hostPortMap",
  "-e", "AIRFLOW_HOME=/home/datalab/runtime/airflow",
  "-e", "AIRFLOW__CORE__LOAD_EXAMPLES=False",
  "-e", "AIRFLOW__CORE__EXECUTOR=LocalExecutor",
  "-e", "AIRFLOW__CORE__PARALLELISM=16",
  "-e", "AIRFLOW__CORE__MAX_ACTIVE_TASKS_PER_DAG=8",
  "-e", "AIRFLOW__CORE__MAX_ACTIVE_RUNS_PER_DAG=4",
  "-e", "AIRFLOW__CORE__DAGS_FOLDER=$airflowDagsFolder",
  "-e", "AIRFLOW__DATABASE__SQL_ALCHEMY_CONN=postgresql+psycopg2://admin:admin@localhost:5432/datalab",
  "-e", "DATALAB_AIRFLOW_DAGS_FOLDER=$airflowDagsFolder",
  "-e", "DATALAB_SPARK_VERBOSE=0",
  "-e", "DATALAB_SPARK_LOG_LEVEL=WARN"
)

$dockerArgs = @(
  "run", "-d", "--name", $NewName,
  "--user", "root",
  "--workdir", "/",
  "--label", "com.docker.compose.project=",
  "--label", "com.docker.compose.service=",
  "--label", "com.docker.compose.oneoff="
) + $portArgs + $volumeArgs + $envArgs + @($resolvedImage, "sleep", "infinity")

Write-Host "Starting copied container '$NewName'..."
& docker @dockerArgs
if ($LASTEXITCODE -ne 0) {
  throw "docker run failed for '$NewName'."
}

$uiMapFile = "/home/datalab/runtime/ui-port-map.env"
$uiMapScript = @'
cat > __UI_MAP_FILE__ <<'EOF'
DATALAB_UI_HOST=__UI_HOST__
DATALAB_HOST_PORT_MAP=__HOST_PORT_MAP__
EOF
sed -i 's/\r$//' __UI_MAP_FILE__ 2>/dev/null || true
chmod 644 __UI_MAP_FILE__ || true
'@
$uiMapScript = $uiMapScript.Replace("__UI_MAP_FILE__", $uiMapFile).Replace("__UI_HOST__", $UiHost).Replace("__HOST_PORT_MAP__", $hostPortMap)
Invoke-ContainerShellScript -ContainerName $NewName -ScriptText $uiMapScript -Shell "bash" -RemotePath "/tmp/datalab-copy-ui-map.sh"

$bootstrapScript = @'
set -e
# New copied container should start from a clean Kafka metadata state.
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

# Keep login-shell Airflow defaults aligned with the copied-container topology.
cat > /etc/profile.d/datalab-path.sh <<'EOF'
# Data Lab environment and PATH additions (applied to all users)
export SPARK_HOME=/opt/spark
export HADOOP_HOME=/opt/hadoop
export HADOOP_COMMON_LIB_NATIVE_DIR=/opt/hadoop/lib/native
export HIVE_HOME=/opt/hive
export TRINO_HOME=/opt/trino
export KAFKA_HOME=/opt/kafka
export APICURIO_REGISTRY_HOME=/opt/apicurio-registry
export MARQUEZ_HOME=/opt/marquez
export MARQUEZ_WEB_HOME=/opt/marquez-web
export PROMETHEUS_HOME=/opt/prometheus
export GRAFANA_HOME=/opt/grafana
export OPENLINEAGE_SPARK_HOME=/opt/openlineage-spark
export MONGO_HOME=/opt/mongodb
export JAVA_HOME=/usr/lib/jvm/java-11-openjdk-amd64
export LD_LIBRARY_PATH="/opt/hadoop/lib/native:${LD_LIBRARY_PATH}"
export PATH="/home/datalab/app/bin:${PATH}"
# Force a shared workspace path so root and datalab use the same mounts
export WORKSPACE="/home/datalab"
export RUNTIME_ROOT="${WORKSPACE}/runtime"
export LAKEHOUSE_STACK_ROOT="${WORKSPACE}/lakehouse"
export AIRFLOW_HOME="${AIRFLOW_HOME:-${RUNTIME_ROOT}/airflow}"
export DATALAB_AIRFLOW_DAGS_FOLDER="${DATALAB_AIRFLOW_DAGS_FOLDER:-__AIRFLOW_DAGS_FOLDER__}"
export AIRFLOW__CORE__DAGS_FOLDER="${AIRFLOW__CORE__DAGS_FOLDER:-${DATALAB_AIRFLOW_DAGS_FOLDER}}"
export AIRFLOW__CORE__LOAD_EXAMPLES="${AIRFLOW__CORE__LOAD_EXAMPLES:-False}"
export AIRFLOW__CORE__EXECUTOR="${AIRFLOW__CORE__EXECUTOR:-LocalExecutor}"
export AIRFLOW__DATABASE__SQL_ALCHEMY_CONN="${AIRFLOW__DATABASE__SQL_ALCHEMY_CONN:-postgresql+psycopg2://${POSTGRES_USER:-admin}:${POSTGRES_PASSWORD:-admin}@localhost:${POSTGRES_PORT:-5432}/${POSTGRES_DB:-datalab}}"
export DBT_PROFILES_DIR="${WORKSPACE}/dbt"
export DBT_PACKAGE_INSTALL_PATH="${RUNTIME_ROOT}/dbt/dbt_packages"
export TF_DATA_DIR="${RUNTIME_ROOT}/terraform/.terraform"
export PATH="$JAVA_HOME/bin:$PATH:${SPARK_HOME}/bin:${HADOOP_HOME}/bin:${HADOOP_HOME}/sbin:${HIVE_HOME}/bin:${KAFKA_HOME}/bin:${MONGO_HOME}/bin"
EOF
chmod 0644 /etc/profile.d/datalab-path.sh || true

# Seed the persisted Airflow config so copied containers do not fall back to
# SQLite/SequentialExecutor when users inspect airflow.cfg directly.
mkdir -p /home/datalab/runtime/airflow
su - datalab -c "airflow config get-value core executor >/dev/null 2>&1 || airflow version >/dev/null 2>&1 || true"
cfg=/home/datalab/runtime/airflow/airflow.cfg
if [ -f "$cfg" ]; then
  sed -i -E "s|^dags_folder = .*|dags_folder = __AIRFLOW_DAGS_FOLDER__|" "$cfg" || true
  sed -i -E "s|^executor = .*|executor = LocalExecutor|" "$cfg" || true
  sed -i -E "s|^parallelism = .*|parallelism = 16|" "$cfg" || true
  sed -i -E "s|^max_active_tasks_per_dag = .*|max_active_tasks_per_dag = 8|" "$cfg" || true
  sed -i -E "s|^max_active_runs_per_dag = .*|max_active_runs_per_dag = 4|" "$cfg" || true
  sed -i -E "s|^load_examples = .*|load_examples = False|" "$cfg" || true
  sed -i -E "s|^sql_alchemy_conn = .*|sql_alchemy_conn = postgresql+psycopg2://admin:admin@localhost:5432/datalab|" "$cfg" || true
  chown datalab:datalab "$cfg" 2>/dev/null || true
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
  /home/datalab/derby.log
)
for p in "${owned_paths[@]}"; do
  [ -e "$p" ] || continue
  chown -R datalab:datalab "$p" 2>/dev/null || true
  chmod -R u+rwX,go+rX "$p" 2>/dev/null || true
done
'@
$bootstrapScript = $bootstrapScript.Replace("__AIRFLOW_DAGS_FOLDER__", $airflowDagsFolder)
$bootstrapScript = $bootstrapScript -replace "`r", ""
Invoke-ContainerShellScript -ContainerName $NewName -ScriptText $bootstrapScript -Shell "bash" -RemotePath "/tmp/datalab-copy-bootstrap.sh"

Write-Output "Container $NewName started from image $resolvedImage."
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
Write-Output "Runtime volume: ${runtimeVolumeName}:/home/datalab/runtime"
if (-not $BindProjectFiles) {
  Write-Output "Mode: isolated (no auto bind mounts from this project)."
}

$serviceMap = @{
  8080  = @{ Name = "Airflow";         Path = "/" }
  9090  = @{ Name = "Spark Master";    Path = "/" }
  18080 = @{ Name = "Spark History";   Path = "/" }
  4040  = @{ Name = "Spark App UI";    Path = "/" }
  9870  = @{ Name = "HDFS NameNode";   Path = "/" }
  8088  = @{ Name = "YARN ResourceMgr";Path = "/" }
  9002  = @{ Name = "Kafka UI";        Path = "/" }
  8181  = @{ Name = "pgAdmin UI"; Path = "/" }
  8083  = @{ Name = "Mongo Express UI"; Path = "/" }
  8084  = @{ Name = "Redis Commander UI"; Path = "/" }
  8085  = @{ Name = "Schema Registry API"; Path = "/apis/registry/v3" }
  8086  = @{ Name = "Kafka Connect API"; Path = "/connectors" }
  8091  = @{ Name = "Trino"; Path = "/" }
  8090  = @{ Name = "Superset"; Path = "/" }
  5000  = @{ Name = "Marquez API"; Path = "/api/v1/namespaces" }
  3000  = @{ Name = "Marquez UI"; Path = "/" }
  9095  = @{ Name = "Prometheus UI"; Path = "/" }
  3001  = @{ Name = "Grafana UI"; Path = "/" }
  9004  = @{ Name = "MinIO API"; Path = "/" }
  9005  = @{ Name = "MinIO Console"; Path = "/" }
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
foreach ($mapping in $resolvedDefaultPorts) {
  $parts = $mapping.Split(":")
  $hostPort = [int]$parts[0]
  $containerPort = [int]$parts[1]
  if ($containerPort -eq 9083) {
    Write-Output ("  - Hive Metastore: thrift://{0}:{1}" -f $UiHost, $hostPort)
  }
  if ($containerPort -eq 10000) {
    Write-Output ("  - HiveServer2 Thrift: thrift://{0}:{1}" -f $UiHost, $hostPort)
  }
}

Write-Output "Enter with: docker exec -it -w / $NewName bash"
