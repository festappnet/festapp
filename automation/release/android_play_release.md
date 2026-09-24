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
`ANDROID_UPLOAD_CERT_SHA256`. Both environments contain the same
`ANDROID_ARTIFACT_PASSPHRASE`; GitHub stores only an AES-256 encrypted candidate
archive because the source repository is public.

The candidate workflow pins the source branch to its exact remote SHA, checks
tenant drift, builds on Ubuntu, verifies the AAB package/version/signature,
rejects personal path or identity markers, and stores the AAB plus a technical
receipt as a private GitHub Actions artifact for 30 days. The artifact name is
`android-candidate-<tenant>-<sourceSha>`; the workflow summary records its run
ID, package, version code, source SHA, release-tooling SHA and AAB SHA-256.

`Android production batch` accepts one to thirty fully identified candidates.
Every item must include `tenant`, `packageName`, `versionCode`, `sourceSha`,
`toolingSha`, `artifactSha256`, `candidateRunId`, and
`action: "production-completed"`. It
refuses an advanced branch, downloads only the exact GitHub artifact, repeats all identity checks, performs
the binary-only production upload, and reads the completed version back from
Google Play. Dispatching this workflow is still a production mutation and needs
fresh authorization for every listed package and artifact.

## Reusable Google Play operations

`Google Play gateway` is the generic store-management entry point for Festapp
and future products such as Mendelio. It supports batches of up to thirty
requests and provides track, listing, review, user and per-app grant inventory;
localized listing updates; exact review replies; and per-app grant updates.

The dispatch input contains only tenant, package, operation and the SHA-256 of
the full request. The full request is supplied through the protected
environment secret `PLAY_OPERATION_REQUEST_JSON`, keeping review text and
account identities out of public workflow inputs. Each environment also sets
`PLAY_ALLOWED_REPOSITORY` to the exact caller repository. Full reports are
encrypted before artifact upload and retained for 30 days. Mutations require a
deterministic confirmation derived from the exact content and an independent
readback before success.

Prepare the protected request with
`node automation/release/google_play_request.mjs input.json request.json`.
The helper canonicalizes the JSON, adds the exact confirmation for mutations,
writes the result with owner-only permissions and prints only its safe selector
and SHA-256. Store the exact output bytes in the environment secret before
dispatching the matching selector.

The gateway only runs on a GitHub-hosted Linux runner. Product-specific
manifests and metadata remain in their private canonical repository and are
converted to the protected request at dispatch time.
