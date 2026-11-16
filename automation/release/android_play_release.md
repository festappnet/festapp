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
```

The original upload keystore is configured only through ignored
`android/key.properties`. Local tooling can run preflight, but it
cannot inspect or mutate Google Play. Every Play API call and production upload
runs exclusively through the repository's GitHub-hosted Linux gateway.

The version name and code come from main-owned
`automation/release/software-version.conf`, shared with web and iOS. Upgrade a
tenant to that main generation before dispatch; package-specific version bumps
are forbidden. The local `-Build` operation is rejected.

The read-only check creates a temporary Google Play edit because track reads are
edit-scoped, then always deletes/discards it. It never commits a release.
Production still fails closed unless package, source SHA, version code, signing
identity and exact confirmation match. Screenshot staging is deterministic and
validated locally, while the production lane skips all screenshot, image, and
listing mutations.

## GitHub-hosted batches

`Android candidate batch` is the canonical remote build entry point. Dispatch it
from `main` with a JSON array of one to thirty tenant IDs. Up to five isolated
tenant jobs run on Linux. No Android build runs on a personal workstation.

The `reuse_build_cache` dispatch option defaults to `true`. A warm-up job seeds
shared Gradle state, then tenant jobs restore and update the same cache family.
Gradle task output caching is enabled; Gradle validates each task's actual inputs,
including tenant-specific resources and configuration. CargoKit's generic Rust
compilation directories and public Cargo registry are cached separately across tenants. Native builds use committed Cargo lockfiles with `--locked`. Their key covers
tracked native sources, dependency lockfile, Flutter/Gradle/NDK configuration,
runner image, Rust compiler and all app Gradle settings except namespace and
application ID. Signing inputs and final AAB/APK output directories are excluded.

Cache entries restore from the newest compatible prefix. The first selected
tenant is the sole writer for each batch; all tenants can read. Gradle warm state
is saved only on a cold cache, and the writer updates compilation state even if
later packaging fails. Complete native state is saved after successful builds
only when a compatible native snapshot does not already exist. This avoids
duplicating multi-gigabyte Gradle state for every matrix member. A cache-service failure permits a cold build. The workflow
summary records the restored Gradle/native keys; a key match is evidence of reuse,
not a measured speedup. Flutter SDK and Pub caches remain enabled independently.

For an explicit cold diagnostic build, dispatch `reuse_build_cache=false`. This
skips the shared warm-up, restore and save operations. Cache reuse never replaces
the final package, version, signing and source verification or the encrypted
candidate/production artifact flow. Sharing intermediates does not authorize a
release of another tenant.

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
receipt as an encrypted GitHub Actions artifact for 7 days. The artifact name is
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

Candidate artifacts provide a 7-day promotion window, not a release archive.
Promote the exact verified candidate within that window. After expiry, build and
verify a new candidate and obtain authorization for its new run ID and digest;
do not reuse an expired candidate identity. Encrypted raw AABs remain available
for validation recovery for 3 days. Revalidation also produces a 7-day candidate.
Keep an independently verified archive before relying on a candidate for longer
term recovery. Small Google Play operation receipts retain their 30-day policy.
Changing workflow retention affects new uploads only; it does not shorten the
expiry of existing artifacts.

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
