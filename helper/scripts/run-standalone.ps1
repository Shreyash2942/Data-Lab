Param(
  [string]$Name = "datalab",
  [string]$Image = "data-lab:latest",
  [string]$ExtraPorts = "",
  [string]$ExtraVolumes = ""
)

# Create a non-stackable container with ports and host mounts for the workspace.
if ($PSVersionTable.PSVersion.Major -ge 7) {
  $PSNativeCommandUseErrorActionPreference = $false
}
$repoRoot = (Resolve-Path (Join-Path $PSScriptRoot "..\..")).Path
$datalabDir = Join-Path $repoRoot "datalabcontainer"
$stacksDir = Join-Path $repoRoot "stacks"

$defaultPortMappings = @(
  "8080:8080", "4040:4040", "9090:9090", "18080:18080",
  "9092:9092", "9870:9870", "8088:8088", "10000:10000",
  "10001:10001", "9002:9002", "8082:8082", "8083:8083", "8084:8084", "8181:8181",
  "5432:5432", "27017:27017", "6379:6379"
)

$hostPortMapEntries = @()
foreach ($mapping in $defaultPortMappings) {
  $parts = $mapping.Split(":")
  $hostPort = [int]$parts[0]
  $containerPort = [int]$parts[1]
  $hostPortMapEntries += "$containerPort=$hostPort"
}
$hostPortMap = $hostPortMapEntries -join ","

$existingNames = @(docker container ls -a --format "{{.Names}}" 2>$null)
if ($existingNames -contains $Name) {
  docker rm -f $Name 2>$null | Out-Null
}

docker run -d --name $Name `
  --user root `
  --workdir / `
  --label com.docker.compose.project= `
  --label com.docker.compose.service= `
  --label com.docker.compose.oneoff= `
  -e DATALAB_UI_HOST=localhost `
  -e DATALAB_HOST_PORT_MAP="$hostPortMap" `
  -p 8080:8080 -p 4040:4040 -p 9090:9090 -p 18080:18080 `
  -p 9092:9092 -p 9870:9870 -p 8088:8088 -p 10000:10000 -p 10001:10001 -p 9002:9002 `
  -p 8082:8082 -p 8083:8083 -p 8084:8084 -p 8181:8181 `
  -p 5432:5432 -p 27017:27017 -p 6379:6379 `
  $ExtraPorts `
  -v ${datalabDir}\app:/home/datalab/app `
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
  -v ${stacksDir}\mongodb:/home/datalab/mongodb `
  -v ${stacksDir}\postgres:/home/datalab/postgres `
  -v ${stacksDir}\redis:/home/datalab/redis `
  -v ${stacksDir}\hudi:/home/datalab/hudi `
  -v ${stacksDir}\iceberg:/home/datalab/iceberg `
  -v ${stacksDir}\delta:/home/datalab/delta `
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
docker exec $Name sh -lc $uiMapScript 2>$null | Out-Null

Write-Output "Container $Name started from $Image."
Write-Output "Enter with: docker exec -it -w / $Name bash"
