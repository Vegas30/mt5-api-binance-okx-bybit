param(
    [string]$TerminalDataPath = 'C:\Users\RenamedUser\AppData\Roaming\MetaQuotes\Terminal\D0E8209F77C8CF37AD8BF550E51FF075'
)

$ErrorActionPreference = 'Stop'
$repoRoot = Split-Path -Parent $PSScriptRoot
$source = Join-Path $repoRoot 'mql5\Experts\Proboy\Proboy.mq5'
$destinationDirectory = Join-Path $TerminalDataPath 'MQL5\Experts\Proboy'
$destination = Join-Path $destinationDirectory 'Proboy.mq5'

if (-not (Test-Path -LiteralPath $source)) {
    throw "Source file not found: $source"
}

New-Item -ItemType Directory -Force -Path $destinationDirectory | Out-Null
Copy-Item -LiteralPath $source -Destination $destination -Force
Write-Host "Deployed $source to $destination"
