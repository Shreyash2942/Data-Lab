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
foreach ($p in $resolvedDefaultPorts) { $portArgs += @("-p", $p) }
foreach ($p in $normalizedExtraPorts) { $portArgs += @("-p", $p) }

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
Write-Output "Enter with: docker exec -it -w / $NewName bash"
