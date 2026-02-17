Param(
  [string]$SourceName = "datalab",
  [string]$NewName = "",
  [string[]]$ExtraPorts = @()
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

function Test-ContainerExists {
  Param([string]$Name)
  $names = docker container ls -a --format "{{.Names}}"
  return ($names -contains $Name)
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
  "10001:10001", "9002:9002"
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
      docker stop $NewName | Out-Null
      docker rm $NewName | Out-Null
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

$portArgs = @()
foreach ($p in $defaultPorts) { $portArgs += @("-p", $p) }
foreach ($p in $ExtraPorts) { $portArgs += @("-p", $p) }

$volumeArgs = @()
foreach ($v in $collectedVolumes) { $volumeArgs += @("-v", $v) }

$dockerArgs = @(
  "run", "-d", "--name", $NewName,
  "--user", "root",
  "--workdir", "/",
  "--label", "com.docker.compose.project=",
  "--label", "com.docker.compose.service=",
  "--label", "com.docker.compose.oneoff="
) + $portArgs + $volumeArgs + @($image, "sleep", "infinity")

Write-Host "Starting copied container '$NewName'..."
& docker @dockerArgs
if ($LASTEXITCODE -ne 0) {
  throw "docker run failed for '$NewName'."
}

Write-Output "Container $NewName started from image $image."
if ($collectedVolumes.Count -gt 0) {
  Write-Output "Mounted: $($collectedVolumes -join ', ')"
}
Write-Output "Enter with: docker exec -it -w / $NewName bash"
