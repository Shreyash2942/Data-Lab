Param(
  [switch]$DryRun
)

$ErrorActionPreference = "Stop"
if ($PSVersionTable.PSVersion.Major -ge 7) {
  $PSNativeCommandUseErrorActionPreference = $false
}

$buildSourceImages = @(
  "quay.io/debezium/connect:3.4.0.Final",
  "marquezproject/marquez:0.50.0",
  "marquezproject/marquez-web:0.50.0",
  "prom/prometheus:v3.2.1",
  "grafana/grafana:11.5.2",
  "apicurio/apicurio-registry:3.2.0"
)

$containerImages = @(docker ps -a --format "{{.Image}}" 2>$null)
$localImages = @(docker image ls --format "{{.Repository}}:{{.Tag}}" 2>$null)

foreach ($image in $buildSourceImages) {
  if ($localImages -notcontains $image) {
    Write-Host "[skip] $image (not present locally)"
    continue
  }

  if ($containerImages -contains $image) {
    Write-Host "[keep] $image (used by at least one container)"
    continue
  }

  if ($DryRun) {
    Write-Host "[remove] $image"
    continue
  }

  docker image rm $image | Out-Null
  Write-Host "[removed] $image"
}
