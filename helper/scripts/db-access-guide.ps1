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
$minioApiPort = Get-MappedPort -Container $container -ContainerPort 9004
$minioConsolePort = Get-MappedPort -Container $container -ContainerPort 9005
$mongoExpressPort = Get-MappedPort -Container $container -ContainerPort 8083
$redisCommanderPort = Get-MappedPort -Container $container -ContainerPort 8084
$pgAdminInContainerPort = Get-MappedPort -Container $container -ContainerPort 8181

$pgAdminContainer = Get-RunningContainerByName -ExactName "pgadmin-$container"
$pgAdminPort = $pgAdminInContainerPort
if (-not $pgAdminPort -and $pgAdminContainer) {
  $pgAdminPort = Get-MappedPort -Container $pgAdminContainer -ContainerPort 80
}

Write-Output "=== Data Lab Access Guide ==="
Write-Output "Container: $container"
Write-Output ""
Write-Output "Enter credentials you want to use in tools:"
$pgUser = Prompt-WithDefault -Label "PostgreSQL username" -DefaultValue "admin"
$pgPassword = Prompt-WithDefault -Label "PostgreSQL password" -DefaultValue "admin"
$mongoUser = Prompt-WithDefault -Label "MongoDB username" -DefaultValue "admin"
$mongoPassword = Prompt-WithDefault -Label "MongoDB password" -DefaultValue "admin"
$redisPassword = Prompt-WithDefault -Label "Redis password" -DefaultValue "admin"
$minioAccessKey = Prompt-WithDefault -Label "MinIO access key" -DefaultValue "minio_admin"
$minioSecretKey = Prompt-WithDefault -Label "MinIO secret key" -DefaultValue "minioadmin"
$minioRegion = Prompt-WithDefault -Label "MinIO region" -DefaultValue "us-east-1"
$minioBucket = Prompt-WithDefault -Label "MinIO bucket example" -DefaultValue "datalab"
Write-Output ""

Write-Output "=== Browser UIs ==="
if ($pgAdminPort) { Write-Output ("pgAdmin:                http://{0}:{1}/" -f $UiHost, $pgAdminPort) }
if ($mongoExpressPort) { Write-Output ("Mongo Express:          http://{0}:{1}/" -f $UiHost, $mongoExpressPort) }
if ($redisCommanderPort) { Write-Output ("Redis Commander:        http://{0}:{1}/" -f $UiHost, $redisCommanderPort) }
if ($minioConsolePort) { Write-Output ("MinIO Console:          http://{0}:{1}/" -f $UiHost, $minioConsolePort) }
if (-not $pgAdminPort -and -not $mongoExpressPort -and -not $redisCommanderPort -and -not $minioConsolePort) {
  Write-Output "No DB or object-storage UI ports are currently published."
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
Write-Output "=== MinIO (S3 API / SDKs / CLI) ==="
if ($minioApiPort) {
  $minioEndpoint = "http://{0}:{1}" -f $UiHost, $minioApiPort
  Write-Output ("Endpoint:   {0}" -f $minioEndpoint)
  if ($minioConsolePort) {
    Write-Output ("Console:    http://{0}:{1}/" -f $UiHost, $minioConsolePort)
  }
  Write-Output ("Access Key: {0}" -f $minioAccessKey)
  Write-Output ("Secret Key: {0}" -f $minioSecretKey)
  Write-Output ("Region:     {0}" -f $minioRegion)
  Write-Output ("Bucket URI: s3://{0}/" -f $minioBucket)
  Write-Output ("Path Style: true")
  Write-Output ("AWS env:    AWS_ACCESS_KEY_ID={0}" -f $minioAccessKey)
  Write-Output ("            AWS_SECRET_ACCESS_KEY={0}" -f $minioSecretKey)
  Write-Output ("            AWS_DEFAULT_REGION={0}" -f $minioRegion)
  Write-Output ("            AWS_ENDPOINT_URL={0}" -f $minioEndpoint)
  Write-Output ("AWS CLI:    aws --endpoint-url {0} s3 ls" -f $minioEndpoint)
  Write-Output ("Bucket cmd: aws --endpoint-url {0} s3 mb s3://{1}" -f $minioEndpoint, $minioBucket)
} else {
  Write-Output "MinIO API port is not published."
}

Write-Output ""
Write-Output "Tip: Run again anytime after port/container changes."
