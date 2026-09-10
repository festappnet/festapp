# Android / Google Play release

The canonical package and expected release branch come from the exact private
manifest selected by `FESTAPP_RELEASE_MANIFEST`. Default operation remains local preflight;
the explicitly gated write operation publishes the verified build directly to
production. The Google identity may hold account-level release permission for
all apps, but this repository wrapper remains locked to the manifest package.

```powershell
$env:FESTAPP_RELEASE_MANIFEST = 'C:\path\to\private-release-listing\config.json'
$env:FESTAPP_CANONICAL_CUTOVER_RELEASE = '1' # required for the self-hosted cutover build
.\automation\release\android_release.ps1 -Preflight
.\automation\release\android_release.ps1 -Build
```

The original upload keystore is configured only through ignored
`android/key.properties`. Local tooling can prepare or build a candidate, but it
cannot inspect or mutate Google Play. Every Play API call and production upload
runs exclusively through the repository's GitHub-hosted Linux gateway.

The read-only check creates a temporary Google Play edit because track reads are
edit-scoped, then always deletes/discards it. It never commits a release.
Production still fails closed unless package, source SHA, version code, signing
identity and exact confirmation match. Screenshot staging is deterministic and
validated locally, while the production lane skips all screenshot, image, and
listing mutations.

## GitHub-hosted batches

`Android candidate batch` is the canonical remote build entry point. Dispatch it
from `main` with a JSON array of one to thirty tenant IDs. A cache-warming Linux
job writes the shared Gradle dependency cache once; up to five isolated tenant
jobs then read it concurrently. Flutter's SDK and Pub package caches are also
enabled. No Android build job runs on macOS or a personal workstation.

Each tenant uses GitHub environments named `android-build-<tenant>` and
`android-production-<tenant>`. Build environments contain
`RELEASE_MANIFEST_JSON`, `ANDROID_UPLOAD_KEYSTORE_B64`,
`ANDROID_KEY_PROPERTIES`, and `ANDROID_UPLOAD_CERT_SHA256`. Production
environments contain `RELEASE_MANIFEST_JSON`, `GOOGLE_PLAY_JSON`, and
`ANDROID_UPLOAD_CERT_SHA256`. Repository-level Cloudflare credentials and the
`FESTAPP_ANDROID_RELEASE_BUCKET` variable provide access to the private R2
artifact store.

The candidate workflow pins the source branch to its exact remote SHA, checks
tenant drift, builds on Ubuntu, verifies the AAB package/version/signature,
rejects personal path or identity markers, and stores the AAB plus a technical
receipt under:

```text
android/releases/<package>/<versionCode>/<sourceSha>/<artifactSha256>.aab
```

`Android production batch` accepts one to thirty fully identified candidates.
Every item must include `tenant`, `packageName`, `versionCode`, `sourceSha`,
`artifactSha256`, and `action: "production-completed"`. It refuses an advanced
branch, downloads only the exact R2 object, repeats all identity checks, performs
the binary-only production upload, and reads the completed version back from
Google Play. Dispatching this workflow is still a production mutation and needs
fresh authorization for every listed package and artifact.
