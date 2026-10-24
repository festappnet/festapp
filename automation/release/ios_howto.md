# iOS build and App Store upload

`ios_build_and_upload.sh` builds and uploads one IPA for the selected tenant.
Submission for review and release are separate, explicitly gated Fastlane lanes.
The script does not prompt for release notes or submit the uploaded build.

## Prerequisites

- macOS, Xcode and valid signing material for the exact app and extensions
- FVM with the Flutter SDK pinned by `automation/project.conf`
- Ruby/Bundler and the dependencies pinned in `fastlane/Gemfile.lock`
- A clean, synchronized release checkout with the selected tenant overlay and
  committed dependency lockfiles
- The private release listing's canonical `config.json`, App Store Connect API
  key and signing inputs provisioned outside this repository

Install the pinned Fastlane dependencies from the repository root:

```bash
(cd automation/release/fastlane && bundle install)
```

`fastlane_setup.sh` checks the existing canonical Fastfile, release manifest and
installed dependencies. It does not install Fastlane or generate a Fastfile.

## Private configuration

Create the ignored `automation/release/.set_appstore_env.sh` using values from
the private configuration source:

```bash
export FESTAPP_RELEASE_MANIFEST="<private-config-root>/<listing>/config.json"
export APP_STORE_CONNECT_KEY_ID="<key-id>"
export APP_STORE_CONNECT_ISSUER_ID="<issuer-id>"
export APP_STORE_CONNECT_KEY_PATH="<private-config-root>/AuthKey_<key-id>.p8"
```

The key path must be absolute, outside this checkout and readable only by its
owner (`chmod 600`). Keep signing keys, provisioning inputs, reviewer credentials
and API secrets in their designated private sources. The manifest supplies the
exact listing identity, metadata and screenshot paths; `project.conf` supplies
the version and build number.

## Build and upload

Once the exact tenant upload is authorized, run from the repository root:

```bash
source automation/release/.set_appstore_env.sh
./automation/release/ios_build_and_upload.sh
```

The script runs local store/client-cutover preflights, renders export options,
prepares signing, resolves dependencies with the enforced lockfile, and builds
with `fvm flutter build ipa`. It requires exactly one IPA in `build/ios/ipa`,
rejects an unexpected OneSignal Location framework, then runs the pinned
`upload_build` lane. A build/upload receipt does not prove processing, review
submission or public availability.

## Metadata, review and release

Release notes come from the private listing metadata, not an interactive prompt.
Use the canonical Fastlane lanes for metadata, reviewer details, privacy URLs,
processed-build checks, build selection and submission. Each write lane retains
its exact identity/version gate. `submit_for_review` requires its own explicit
release authority and confirmation; it configures automatic release after Apple
approval. See the [lane reference](fastlane/README.md) and the checked-in
[Fastfile](fastlane/Fastfile) for the current gates.

For a read-only identity/version check after loading the private environment:

```bash
(cd automation/release/fastlane && bundle exec fastlane ios asc_check)
```

If setup fails, check the external manifest/key paths, key permissions, pinned
Bundler dependencies and exact app signing profiles before retrying. Never
regenerate the canonical Fastfile or substitute another app's credentials.
