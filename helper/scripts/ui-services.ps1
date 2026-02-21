Param(
  [string]$Name = "datalab",
  [string]$FallbackName = "data-lab",
  [string]$UiHost = "localhost"
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"
if ($PSVersionTable.PSVersion.Major -ge 7) {
  $PSNativeCommandUseErrorActionPreference = $false
}

function Resolve-RunningContainer {
  Param([string]$Primary, [string]$Secondary)
  $names = @(docker ps --format "{{.Names}}" 2>$null)
  if ($names -contains $Primary) { return $Primary }
  if ($names -contains $Secondary) { return $Secondary }
  throw "No running Data Lab container found. Tried '$Primary' and '$Secondary'."
}

function Get-MappedUrl {
  Param(
    [string]$Container,
    [int]$ContainerPort,
    [string]$Path = "/"
  )
  $prevEap = $ErrorActionPreference
  $ErrorActionPreference = "Continue"
  try {
    $mapping = docker port $Container "$ContainerPort/tcp" 2>$null
    $exitCode = $LASTEXITCODE
  } finally {
    $ErrorActionPreference = $prevEap
  }
  if ($exitCode -ne 0) { return "(not published)" }
  if (-not $mapping) { return "(not published)" }

  $first = ($mapping | Select-Object -First 1).Trim()
  $parts = $first.Split(":")
  $hostPort = $parts[$parts.Length - 1]
  if (-not ($hostPort -match "^\d+$")) {
    return "(published, unable to parse: $first)"
  }
  return "http://$UiHost`:$hostPort$Path"
}

function Get-MappedPort {
  Param(
    [string]$Container,
    [int]$ContainerPort
  )
  $prevEap = $ErrorActionPreference
  $ErrorActionPreference = "Continue"
  try {
    $mapping = docker port $Container "$ContainerPort/tcp" 2>$null
    $exitCode = $LASTEXITCODE
  } finally {
    $ErrorActionPreference = $prevEap
  }
  if ($exitCode -ne 0) { return "(not published)" }
  if (-not $mapping) { return "(not published)" }

  $first = ($mapping | Select-Object -First 1).Trim()
  $parts = $first.Split(":")
  $hostPort = $parts[$parts.Length - 1]
  if (-not ($hostPort -match "^\d+$")) {
    return "(published, unable to parse: $first)"
  }
  return $hostPort
}

function Get-MappedEndpoint {
  Param(
    [string]$Container,
    [int]$ContainerPort,
    [string]$Scheme
  )
  $hostPort = Get-MappedPort -Container $Container -ContainerPort $ContainerPort
  if ($hostPort -match "^\d+$") {
    return "$Scheme`://$UiHost`:$hostPort"
  }
  return $hostPort
}

$container = Resolve-RunningContainer -Primary $Name -Secondary $FallbackName

Write-Output "=== Data Lab UI Services ==="
Write-Output "Container: $container"
Write-Output ("{0,-20} {1}" -f "Airflow:",          (Get-MappedUrl -Container $container -ContainerPort 8080  -Path "/"))
Write-Output ("{0,-20} {1}" -f "Spark Master:",      (Get-MappedUrl -Container $container -ContainerPort 9090  -Path "/"))
Write-Output ("{0,-20} {1}" -f "Spark History:",     (Get-MappedUrl -Container $container -ContainerPort 18080 -Path "/"))
Write-Output ("{0,-20} {1}" -f "Spark App UI:",      (Get-MappedUrl -Container $container -ContainerPort 4040  -Path "/"))
Write-Output ("{0,-20} {1}" -f "HDFS NameNode:",     (Get-MappedUrl -Container $container -ContainerPort 9870  -Path "/"))
Write-Output ("{0,-20} {1}" -f "YARN ResourceMgr:",  (Get-MappedUrl -Container $container -ContainerPort 8088  -Path "/"))
Write-Output ("{0,-20} {1}" -f "HiveServer2 HTTP:",  (Get-MappedUrl -Container $container -ContainerPort 10001 -Path "/cliservice"))
Write-Output ("{0,-20} {1}" -f "Kafka UI:",          (Get-MappedUrl -Container $container -ContainerPort 9002  -Path "/"))
Write-Output ("{0,-20} {1}" -f "Adminer UI:",       (Get-MappedUrl -Container $container -ContainerPort 8082  -Path "/"))
Write-Output ("{0,-20} {1}" -f "Mongo Express UI:", (Get-MappedUrl -Container $container -ContainerPort 8083  -Path "/"))
Write-Output ("{0,-20} {1}" -f "Redis Commander UI:", (Get-MappedUrl -Container $container -ContainerPort 8084 -Path "/"))
Write-Output ("{0,-20} {1}" -f "pgAdmin UI:",      (Get-MappedUrl -Container $container -ContainerPort 8181 -Path "/"))
Write-Output ("{0,-20} {1}" -f "PostgreSQL (DB):",  (Get-MappedEndpoint -Container $container -ContainerPort 5432  -Scheme "postgresql"))
Write-Output ("{0,-20} {1}" -f "MongoDB (DB):",     (Get-MappedEndpoint -Container $container -ContainerPort 27017 -Scheme "mongodb"))
Write-Output ("{0,-20} {1}" -f "Redis (DB):",       (Get-MappedEndpoint -Container $container -ContainerPort 6379  -Scheme "redis"))
Write-Output ""
Write-Output "Note: PostgreSQL/MongoDB/Redis entries are DB endpoints, not HTTP web UIs."
