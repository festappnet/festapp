[CmdletBinding(DefaultParameterSetName='Preflight')]
param(
  [Parameter(ParameterSetName='Preflight')][switch]$Preflight,
  [Parameter(Mandatory, ParameterSetName='Build')][switch]$Build,
  [Parameter(Mandatory, ParameterSetName='PlayCheck')][switch]$PlayCheck,
  [Parameter(Mandatory, ParameterSetName='Production')][switch]$UploadProduction,
  [Parameter(Mandatory, ParameterSetName='Production')]
  [ValidatePattern('^[0-9A-Fa-f]{64}$')]
  [string]$ExpectedUploadSha256,
  [string]$Confirmation
)
$ErrorActionPreference = 'Stop'
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
$versionLine = (Select-String -Path pubspec.yaml -Pattern '^version:\s*(.+)$').Matches.Groups[1].Value.Trim()
$parts = $versionLine.Split('+')
if ($parts.Count -ne 2) { throw 'Canonical version has no build number' }
$versionName, $versionCode = $parts
$treeDirty = [bool](git status --porcelain=v1)
if (($Build -or $UploadProduction) -and $treeDirty) { throw 'Release build/upload requires a clean committed source tree' }

function Require-Command([string]$Name) { if (-not (Get-Command $Name -ErrorAction SilentlyContinue)) { throw "Missing command: $Name" } }
function Assert-SigningConfig {
  $properties = Join-Path $root 'android/key.properties'
  if (-not (Test-Path -LiteralPath $properties)) { throw 'BLOCKED: android/key.properties is absent; securely provide the original upload-key configuration. No replacement key will be generated.' }
  $safe = @{}
  foreach ($line in Get-Content -LiteralPath $properties) {
    if ($line -match '^\s*(keyAlias|storeFile)\s*=\s*(.+?)\s*$') { $safe[$matches[1]] = $matches[2] }
  }
  if (-not $safe.keyAlias -or -not $safe.storeFile) { throw 'Signing config lacks keyAlias or storeFile' }
  $keyPath = $safe.storeFile
  if (-not [IO.Path]::IsPathRooted($keyPath)) { $keyPath = Join-Path (Join-Path $root 'android/app') $keyPath }
  if (-not (Test-Path -LiteralPath $keyPath)) { throw "BLOCKED: configured original upload keystore not found at $keyPath" }
  Write-Host 'Signing key: configured outside the repository'
  Write-Host "Signing alias: $($safe.keyAlias)"

  $all = @{}
  foreach ($line in Get-Content -LiteralPath $properties) {
    if ($line -match '^\s*([^#!][^=]*)=(.*)$') { $all[$matches[1].Trim()] = $matches[2].Trim() }
  }
  if (-not $all.storePassword) { throw 'Signing config lacks storePassword' }
  $env:FESTAPP_KEYTOOL_STOREPASS = $all.storePassword
  try {
    $savedKeytoolErrorPreference = $ErrorActionPreference
    $ErrorActionPreference = 'Continue'
    $certificate = & keytool -list -v -keystore $keyPath -alias $safe.keyAlias -storepass:env FESTAPP_KEYTOOL_STOREPASS 2>&1
    $ErrorActionPreference = $savedKeytoolErrorPreference
    if ($LASTEXITCODE) { throw 'Configured original upload certificate could not be inspected' }
  } finally {
    $ErrorActionPreference = $savedKeytoolErrorPreference
    Remove-Item Env:FESTAPP_KEYTOOL_STOREPASS -ErrorAction SilentlyContinue
  }
  $sha256 = ($certificate | Select-String -Pattern '^\s*SHA256:\s*(.+)$').Matches.Groups[1].Value.Trim()
  $sha1 = ($certificate | Select-String -Pattern '^\s*SHA1:\s*(.+)$').Matches.Groups[1].Value.Trim()
  if (-not $sha256) { throw 'Upload certificate SHA-256 was not returned by keytool' }
  Write-Host "Upload certificate SHA-256: $sha256"
  if ($sha1) { Write-Host "Upload certificate SHA-1: $sha1" }
}

$fvmFallback = Join-Path $env:LOCALAPPDATA 'Pub\Cache\bin'
if (-not (Get-Command fvm -ErrorAction SilentlyContinue) -and (Test-Path (Join-Path $fvmFallback 'fvm.bat'))) {
  $env:PATH = "$fvmFallback;$env:PATH"
}
Require-Command git; Require-Command fvm; Require-Command java; Require-Command node; Require-Command keytool
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
if ($env:GOOGLE_PLAY_JSON_KEY) {
  if (-not (Test-Path -LiteralPath $env:GOOGLE_PLAY_JSON_KEY)) { throw 'GOOGLE_PLAY_JSON_KEY path is unreadable' }
  if ($env:GOOGLE_PLAY_JSON_KEY.StartsWith($root, [StringComparison]::OrdinalIgnoreCase)) {
    throw 'Play credential must stay outside Git/repository'
  }
}
Write-Host "Package: $package"
Write-Host "Version: $versionName ($versionCode)"
Write-Host "Source: $((git rev-parse HEAD).Trim())"
$cutoverPreflightArgs = @('automation/release/client_cutover_preflight.mjs')
if ($env:FESTAPP_CANONICAL_CUTOVER_RELEASE -eq '1') { $cutoverPreflightArgs += '--require-canonical-cutover' }
node @cutoverPreflightArgs
if ($LASTEXITCODE) { throw 'Client cutover preflight failed' }

if ($Build) {
  Assert-SigningConfig
  $aab = Join-Path $root 'build/app/outputs/bundle/release/app-release.aab'
  if (Test-Path -LiteralPath $aab) { Remove-Item -LiteralPath $aab -Force }
  fvm flutter pub get --enforce-lockfile
  fvm flutter build appbundle --release --build-name $versionName --build-number $versionCode
  if ($LASTEXITCODE) { throw 'AAB build failed' }
  if (-not (Test-Path $aab)) { throw 'Expected AAB missing' }
  $hash = (Get-FileHash -Algorithm SHA256 $aab).Hash.ToLowerInvariant()
  Write-Host "AAB: $aab"
  Write-Host "AAB SHA-256: $hash"
} elseif ($PlayCheck -or $UploadProduction) {
  Require-Command bundle
  if (-not $env:GOOGLE_PLAY_JSON_KEY) { throw 'BLOCKED: GOOGLE_PLAY_JSON_KEY is not set to a least-privilege credential outside Git' }
  if ($UploadProduction) {
    $uploadPath = if ($env:PLAY_AAB_PATH) {
      (Resolve-Path -LiteralPath $env:PLAY_AAB_PATH).Path
    } else {
      (Resolve-Path -LiteralPath (Join-Path $root 'build/app/outputs/bundle/release/app-release.aab')).Path
    }
    $expectedHash = $ExpectedUploadSha256.ToLowerInvariant()
    $actualHash = (Get-FileHash -Algorithm SHA256 -LiteralPath $uploadPath).Hash.ToLowerInvariant()
    if ($actualHash -ne $expectedHash) {
      throw "Refusing AAB SHA-256 $actualHash; expected authorized hash $expectedHash"
    }
    # Fastlane must consume the exact file whose hash was authorized above.
    $env:PLAY_AAB_PATH = $uploadPath
    Write-Host "Authorized AAB SHA-256: $actualHash"
  }
  Push-Location automation/release/fastlane
  try {
    if ($PlayCheck) {
      bundle exec fastlane android play_check
      $fastlaneExit = $LASTEXITCODE
      if ($fastlaneExit -ne 0) { throw "Read-only Google Play check failed with exit code $fastlaneExit" }
    } else {
      Assert-SigningConfig
      $env:PLAY_TARGET_TRACK = 'production'
      $env:PLAY_CONFIRMATION = $Confirmation
      bundle exec fastlane android play_production
      $fastlaneExit = $LASTEXITCODE
      if ($fastlaneExit -ne 0) { throw "Google Play production upload failed with exit code $fastlaneExit" }
    }
  } finally { Pop-Location }
} else {
  node automation/release/stage_google_play_metadata.mjs
  if ($LASTEXITCODE) { throw 'Metadata staging failed' }
  Write-Host 'Preflight passed. Signing and Play access are checked only by their explicit modes.'
}
