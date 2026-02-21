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

  if ($exitCode -ne 0 -or -not $mapping) { return "" }
  $first = ($mapping | Select-Object -First 1).Trim()
  $parts = $first.Split(":")
  $hostPort = $parts[$parts.Length - 1]
  if ($hostPort -notmatch "^\d+$") { return "" }
  return $hostPort
}

function Get-RunningContainerByName {
  Param([string]$ExactName)
  $names = @(docker ps --format "{{.Names}}" 2>$null)
  if ($names -contains $ExactName) { return $ExactName }
  return ""
}

function Prompt-WithDefault {
  Param(
    [string]$Label,
    [string]$DefaultValue
  )
  $raw = Read-Host "$Label [$DefaultValue]"
  if ([string]::IsNullOrWhiteSpace($raw)) { return $DefaultValue }
  return $raw.Trim()
}

$container = Resolve-RunningContainer -Primary $Name -Secondary $FallbackName
$pgPort = Get-MappedPort -Container $container -ContainerPort 5432
$mongoPort = Get-MappedPort -Container $container -ContainerPort 27017
$redisPort = Get-MappedPort -Container $container -ContainerPort 6379
$adminerPort = Get-MappedPort -Container $container -ContainerPort 8082
$mongoExpressLegacyPort = Get-MappedPort -Container $container -ContainerPort 8083
$redisCommanderPort = Get-MappedPort -Container $container -ContainerPort 8084
$pgAdminInContainerPort = Get-MappedPort -Container $container -ContainerPort 8181

$pgAdminContainer = Get-RunningContainerByName -ExactName "pgadmin-$container"
$pgAdminPort = $pgAdminInContainerPort
if (-not $pgAdminPort -and $pgAdminContainer) {
  $pgAdminPort = Get-MappedPort -Container $pgAdminContainer -ContainerPort 80
}

$mongoExpressModernContainer = Get-RunningContainerByName -ExactName "mongo-express-$container"
$mongoExpressModernPort = ""
if ($mongoExpressModernContainer) {
  $mongoExpressModernPort = Get-MappedPort -Container $mongoExpressModernContainer -ContainerPort 8081
}

Write-Output "=== Data Lab DB Access Guide ==="
Write-Output "Container: $container"
Write-Output ""
Write-Output "Enter credentials you want to use in tools:"
$pgUser = Prompt-WithDefault -Label "PostgreSQL username" -DefaultValue "admin"
$pgPassword = Prompt-WithDefault -Label "PostgreSQL password" -DefaultValue "admin"
$mongoUser = Prompt-WithDefault -Label "MongoDB username" -DefaultValue "admin"
$mongoPassword = Prompt-WithDefault -Label "MongoDB password" -DefaultValue "admin"
$redisPassword = Prompt-WithDefault -Label "Redis password" -DefaultValue "admin"
Write-Output ""

Write-Output "=== Browser UIs ==="
if ($adminerPort) { Write-Output ("Adminer:                http://{0}:{1}/" -f $UiHost, $adminerPort) }
if ($mongoExpressLegacyPort) { Write-Output ("Mongo Express (legacy): http://{0}:{1}/" -f $UiHost, $mongoExpressLegacyPort) }
if ($mongoExpressModernPort) { Write-Output ("Mongo Express (modern): http://{0}:{1}/" -f $UiHost, $mongoExpressModernPort) }
if ($redisCommanderPort) { Write-Output ("Redis Commander:        http://{0}:{1}/" -f $UiHost, $redisCommanderPort) }
if ($pgAdminPort) { Write-Output ("pgAdmin:                http://{0}:{1}/" -f $UiHost, $pgAdminPort) }
if (-not $adminerPort -and -not $mongoExpressLegacyPort -and -not $mongoExpressModernPort -and -not $redisCommanderPort -and -not $pgAdminPort) {
  Write-Output "No DB UI ports are currently published."
}

Write-Output ""
Write-Output "=== PostgreSQL (VS Code / pgAdmin / PyCharm) ==="
if ($pgPort) {
  Write-Output ("Host:      {0}" -f $UiHost)
  Write-Output ("Port:      {0}" -f $pgPort)
  Write-Output ("Database:  postgres (or datalab)")
  Write-Output ("Username:  {0}" -f $pgUser)
  Write-Output ("Password:  {0}" -f $pgPassword)
  Write-Output ("SSL Mode:  prefer (or disable)")
} else {
  Write-Output "PostgreSQL port is not published."
}

Write-Output ""
Write-Output "=== MongoDB (Compass / VS Code MongoDB extension) ==="
if ($mongoPort) {
  Write-Output ("Host:      {0}" -f $UiHost)
  Write-Output ("Port:      {0}" -f $mongoPort)
  Write-Output ("Username:  {0}" -f $mongoUser)
  Write-Output ("Password:  {0}" -f $mongoPassword)
  Write-Output ("Auth DB:   admin")
  Write-Output ("URI:       mongodb://{0}:{1}@{2}:{3}/admin?authSource=admin" -f $mongoUser, $mongoPassword, $UiHost, $mongoPort)
} else {
  Write-Output "MongoDB port is not published."
}

Write-Output ""
Write-Output "=== Redis (Redis Insight / redis-cli) ==="
if ($redisPort) {
  Write-Output ("Host:      {0}" -f $UiHost)
  Write-Output ("Port:      {0}" -f $redisPort)
  if ([string]::IsNullOrEmpty($redisPassword)) {
    Write-Output "Password:  (none)"
    Write-Output ("URI:       redis://{0}:{1}" -f $UiHost, $redisPort)
  } else {
    Write-Output ("Password:  {0}" -f $redisPassword)
    Write-Output ("URI:       redis://:{0}@{1}:{2}" -f $redisPassword, $UiHost, $redisPort)
  }
} else {
  Write-Output "Redis port is not published."
}

Write-Output ""
Write-Output "Tip: Run again anytime after port/container changes."
