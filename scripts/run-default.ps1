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

$ports = @(
  "4040:4040",   # Spark UI
  "8080:8080",   # Airflow UI
  "8088:8088",   # YARN RM
  "9000:9000",   # Kafka UI
  "9090:9090",   # Spark master UI
  "9092:9092",   # Kafka broker
  "9870:9870",   # HDFS UI
  "10000:10000", # HiveServer2
  "18080:18080"  # Spark history
)

$portArgs = @()
foreach ($p in $ports) { $portArgs += @("-p", $p) }

$cmd = @("docker", "run", "-d", "--name", $Name) + $portArgs + @("data-lab:latest") + $ExtraArgs
& $cmd
