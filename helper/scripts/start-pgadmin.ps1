Param(
  [string]$TargetContainer = "datalab",
  [string]$PgAdminName = "",
  [int]$PgAdminPort = 8181,
  [string]$PgAdminEmail = "admin@admin.com",
  [string]$PgAdminPassword = "admin",
  [string]$DbUser = "admin"
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"
if ($PSVersionTable.PSVersion.Major -ge 7) {
  $PSNativeCommandUseErrorActionPreference = $false
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
  return $true
}

function Resolve-FreePort {
  Param([int]$Preferred)
  $candidate = $Preferred
  while ($candidate -le 65535) {
    if (Test-HostPortFree -Port $candidate) {
      return $candidate
    }
    $candidate++
  }
  throw "No free port found starting from $Preferred."
}

function Resolve-PostgresMappedPort {
  Param([string]$ContainerName)
  $mapping = docker port $ContainerName 5432/tcp 2>$null
  if (-not $mapping) {
    throw "Container '$ContainerName' does not publish Postgres 5432/tcp."
  }

  $first = ($mapping | Select-Object -First 1).Trim()
  $parts = $first.Split(":")
  $hostPort = $parts[$parts.Length - 1]
  if (-not ($hostPort -match "^\d+$")) {
    throw "Unable to parse mapped Postgres port from '$first'."
  }
  return [int]$hostPort
}

function Assert-RunningContainer {
  Param([string]$ContainerName)
  $names = @(docker ps --format "{{.Names}}" 2>$null)
  if ($names -notcontains $ContainerName) {
    throw "Target container '$ContainerName' is not running."
  }
}

Assert-RunningContainer -ContainerName $TargetContainer
$dbPort = Resolve-PostgresMappedPort -ContainerName $TargetContainer

if (-not $PgAdminName) {
  $PgAdminName = "pgadmin-$TargetContainer"
}

$repoRoot = (Resolve-Path (Join-Path $PSScriptRoot "..\..")).Path
$pgAdminDataRoot = Join-Path $repoRoot "datalabcontainer\runtime\pgadmin"
$pgAdminDataDir = Join-Path $pgAdminDataRoot $TargetContainer
New-Item -ItemType Directory -Force -Path $pgAdminDataDir | Out-Null

$serversJsonPath = Join-Path $pgAdminDataDir "servers.json"
$serversJson = @"
{
  "Servers": {
    "1": {
      "Name": "DataLab PostgreSQL ($TargetContainer)",
      "Group": "Servers",
      "Host": "host.docker.internal",
      "Port": $dbPort,
      "MaintenanceDB": "postgres",
      "Username": "$DbUser",
      "SSLMode": "prefer"
    }
  }
}
"@
$utf8NoBom = New-Object System.Text.UTF8Encoding($false)
[System.IO.File]::WriteAllText($serversJsonPath, $serversJson, $utf8NoBom)

$existingNames = @(docker container ls -a --format "{{.Names}}" 2>$null)
if ($existingNames -contains $PgAdminName) {
  docker rm -f $PgAdminName 2>$null | Out-Null
}

$resolvedPgAdminPort = Resolve-FreePort -Preferred $PgAdminPort

$runOutput = docker run -d --name $PgAdminName `
  --add-host host.docker.internal:host-gateway `
  -p "${resolvedPgAdminPort}:80" `
  -e PGADMIN_DEFAULT_EMAIL="$PgAdminEmail" `
  -e PGADMIN_DEFAULT_PASSWORD="$PgAdminPassword" `
  -e PGADMIN_CONFIG_MASTER_PASSWORD_REQUIRED=False `
  -v "${serversJsonPath}:/pgadmin4/servers.json" `
  -v "${pgAdminDataDir}:/var/lib/pgadmin" `
  dpage/pgadmin4
if ($LASTEXITCODE -ne 0) {
  throw "Failed to start pgAdmin container '$PgAdminName'."
}

Write-Output "pgAdmin container '$PgAdminName' started."
if ($resolvedPgAdminPort -ne $PgAdminPort) {
  Write-Output "Requested port $PgAdminPort was busy; using $resolvedPgAdminPort."
}
Write-Output "URL: http://localhost:$resolvedPgAdminPort/"
Write-Output "Login: $PgAdminEmail"
Write-Output "Password: $PgAdminPassword"
Write-Output "Preconfigured server: DataLab PostgreSQL ($TargetContainer) -> host.docker.internal:$dbPort"
Write-Output "If prompted for DB password, use your PostgreSQL password (default: admin)."
