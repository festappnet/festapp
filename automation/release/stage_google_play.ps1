[CmdletBinding()]
param()

$ErrorActionPreference = "Stop"
& node (Join-Path $PSScriptRoot "stage_google_play_metadata.mjs")
if ($LASTEXITCODE -ne 0) { throw "Google Play metadata staging failed." }
