[CmdletBinding(DefaultParameterSetName='Preflight')]
param(
  [Parameter(ParameterSetName='Preflight')][switch]$Preflight,
  [Parameter(Mandatory, ParameterSetName='Build')][switch]$Build
)
$ErrorActionPreference = 'Stop'
if ($Build) { throw 'Android builds run exclusively through the GitHub Android candidate batch workflow.' }
$root = (Resolve-Path (Join-Path $PSScriptRoot '../..')).Path
Set-Location $root
$fvmBin = Join-Path $env:LOCALAPPDATA 'Pub\Cache\bin'
if (Test-Path -LiteralPath $fvmBin) { $env:Path = "$fvmBin;$env:Path" }
if (-not $env:FESTAPP_RELEASE_MANIFEST) { throw 'Set FESTAPP_RELEASE_MANIFEST to the private release config.json' }
$manifestPath = (Resolve-Path -LiteralPath $env:FESTAPP_RELEASE_MANIFEST).Path
if (-not (Test-Path -LiteralPath $manifestPath)) { throw "Internal release manifest not found: $manifestPath" }
$releaseManifest = Get-Content -Raw -LiteralPath $manifestPath | ConvertFrom-Json
$package = $releaseManifest.androidPackage
$expectedBranch = $releaseManifest.releaseBranch
$branch = (git branch --show-current).Trim()
if (-not $package -or -not $expectedBranch) { throw 'Release manifest lacks androidPackage or releaseBranch' }
if ($branch -ne $expectedBranch) { throw "Refusing branch $branch; expected $expectedBranch" }
if ((git remote get-url origin).Trim() -ne 'https://github.com/festappnet/festapp.git') { throw 'Unexpected origin remote' }
if ((Select-String -Path android/app/build.gradle -SimpleMatch "applicationId = `"$package`"").Count -ne 1) { throw 'Package identity mismatch' }
$softwareVersion = (& node automation/release/project_version.mjs --json) | ConvertFrom-Json
if ($LASTEXITCODE) { throw 'Cannot read canonical software version' }
$versionName = $softwareVersion.version
$versionCode = $softwareVersion.build

function Require-Command([string]$Name) { if (-not (Get-Command $Name -ErrorAction SilentlyContinue)) { throw "Missing command: $Name" } }
$fvmFallback = Join-Path $env:LOCALAPPDATA 'Pub\Cache\bin'
if (-not (Get-Command fvm -ErrorAction SilentlyContinue) -and (Test-Path (Join-Path $fvmFallback 'fvm.bat'))) {
  $env:PATH = "$fvmFallback;$env:PATH"
}
Require-Command git; Require-Command fvm; Require-Command java; Require-Command node
$requiredFlutterVersion = (& node (Join-Path $root 'automation/flutter_version.mjs')).Trim()
if ($LASTEXITCODE -ne 0 -or -not $requiredFlutterVersion) {
  throw 'Unable to read FLUTTER_VERSION from automation/project.conf'
}
if ((fvm flutter --version --machine | ConvertFrom-Json).frameworkVersion -ne $requiredFlutterVersion) {
  throw "Flutter must be exactly $requiredFlutterVersion through FVM"
}
$savedErrorPreference = $ErrorActionPreference
$ErrorActionPreference = 'Continue'
$javaVersion = (& java -version 2>&1 | Out-String)
$ErrorActionPreference = $savedErrorPreference
if ($javaVersion -notmatch 'version "17\.') { throw 'JDK must be 17' }
Write-Host "Package: $package"
Write-Host "Version: $versionName ($versionCode)"
Write-Host "Source: $((git rev-parse HEAD).Trim())"
$cutoverPreflightArgs = @('automation/release/client_cutover_preflight.mjs')
if ($env:FESTAPP_CANONICAL_CUTOVER_RELEASE -eq '1') { $cutoverPreflightArgs += '--require-canonical-cutover' }
node @cutoverPreflightArgs
if ($LASTEXITCODE) { throw 'Client cutover preflight failed' }

node automation/release/stage_google_play_metadata.mjs
if ($LASTEXITCODE) { throw 'Metadata staging failed' }
Write-Host 'Preflight passed. Android build and Play publishing run exclusively through GitHub workflows.'
