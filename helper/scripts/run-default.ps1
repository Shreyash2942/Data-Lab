# Runs a container with all service ports mapped on Windows/PowerShell.
# Usage:
#   .\run-default.ps1           # uses container name "datalab"
#   .\run-default.ps1 myname    # uses "myname" as container name
#   .\run-default.ps1 myname --env FOO=bar   # extra args passed after image name

param(
  [string]$Name = "datalab",
  [Parameter(ValueFromRemainingArguments = $true)]
  [string[]]$ExtraArgs
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"
if ($PSVersionTable.PSVersion.Major -ge 7) {
  $PSNativeCommandUseErrorActionPreference = $false
}

$ports = @(
  "4040:4040",   # Spark UI
  "8080:8080",   # Airflow UI
  "8088:8088",   # YARN RM
  "8082:8082",   # Adminer UI
  "8083:8083",   # Mongo Express UI
  "8084:8084",   # Redis Commander UI
  "8181:8181",   # pgAdmin UI
  "9002:9002",   # Kafka UI (Kafdrop)
  "9090:9090",   # Spark master UI
  "9092:9092",   # Kafka broker
  "9870:9870",   # HDFS UI
  "10000:10000", # HiveServer2
  "10001:10001", # HiveServer2 HTTP
  "5432:5432",   # PostgreSQL
  "27017:27017", # MongoDB
  "6379:6379",   # Redis
  "18080:18080"  # Spark history
)

$portArgs = @()
foreach ($p in $ports) { $portArgs += @("-p", $p) }

$cmdArgs = @(
  "run", "-d", "--name", $Name,
  "--user", "root",
  "--workdir", "/",
  "--label", "com.docker.compose.project=",
  "--label", "com.docker.compose.service=",
  "--label", "com.docker.compose.oneoff="
) + $portArgs + @("data-lab:latest") + $ExtraArgs

$existingNames = @(docker container ls -a --format "{{.Names}}" 2>$null)
if ($existingNames -contains $Name) {
  docker rm -f $Name 2>$null | Out-Null
}

& docker @cmdArgs
if ($LASTEXITCODE -ne 0) {
  docker rm -f $Name 2>$null | Out-Null
  throw "docker run failed for '$Name'."
}
