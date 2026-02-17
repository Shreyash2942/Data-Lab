Param(
  [string]$Root = "."
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$rootPath = (Resolve-Path $Root).Path

$targetFiles = @()
$targetFiles += Get-ChildItem -Path $rootPath -Recurse -File -Include *.sh -ErrorAction SilentlyContinue
$targetFiles += Get-ChildItem -Path (Join-Path $rootPath "app") -File |
  Where-Object { $_.Name -in @("start", "stop", "restart", "datalab-check") }
$targetFiles += Get-ChildItem -Path (Join-Path $rootPath "app\\bin") -File -ErrorAction SilentlyContinue

$targetFiles = $targetFiles | Sort-Object -Property FullName -Unique

$updated = 0
foreach ($file in $targetFiles) {
  $bytes = [System.IO.File]::ReadAllBytes($file.FullName)
  $hasCR = $false
  foreach ($b in $bytes) {
    if ($b -eq 13) {
      $hasCR = $true
      break
    }
  }

  if (-not $hasCR) { continue }

  $buffer = New-Object System.Collections.Generic.List[byte]
  for ($i = 0; $i -lt $bytes.Length; $i++) {
    if ($bytes[$i] -eq 13) {
      if ($i + 1 -lt $bytes.Length -and $bytes[$i + 1] -eq 10) {
        continue
      }
      $buffer.Add(10)
      continue
    }
    $buffer.Add($bytes[$i])
  }

  [System.IO.File]::WriteAllBytes($file.FullName, $buffer.ToArray())
  $updated++
  Write-Host "Normalized LF:" $file.FullName
}

Write-Output "Done. Updated $updated file(s)."
