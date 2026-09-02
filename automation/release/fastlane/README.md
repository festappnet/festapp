fastlane documentation
----

# Installation

App-specific publishing data is stored outside this repository. Before running
any lane, set `FESTAPP_RELEASE_MANIFEST` to the exact private `config.json` for
the release listing. Fastlane fails closed when that canonical manifest is
unavailable.

Store copy and screenshots are staged from that repository into temporary
directories. Keystores, API keys, passwords, and service-account credentials do
not belong in either repository.

Make sure you have the latest version of the Xcode command line tools installed:

```sh
xcode-select --install
```

For _fastlane_ installation instructions, see [Installing _fastlane_](https://docs.fastlane.tools/#installing-fastlane)

# Available Actions

## Android

### android play_check

```sh
[bundle exec] fastlane android play_check
```

Read-only package and relevant-track version-code inspection

### android play_internal_draft

```sh
[bundle exec] fastlane android play_internal_draft
```

Exactly gated binary-only upload to internal testing as draft

### android play_production

```sh
[bundle exec] fastlane android play_production
```

Exactly gated full production release for the canonical package and version

----


## iOS

### ios asc_check

```sh
[bundle exec] fastlane ios asc_check
```

Read-only numeric identity and version inspection

### ios signing_check

```sh
[bundle exec] fastlane ios signing_check
```

Read-only signing certificate and provisioning profile inventory

### ios refresh_notification_extension_profile

```sh
[bundle exec] fastlane ios refresh_notification_extension_profile
```

Regenerate only the notification-extension App Store profile after capability changes

### ios refresh_app_store_profiles

```sh
[bundle exec] fastlane ios refresh_app_store_profiles
```

Regenerate both App Store profiles after capability changes

### ios bootstrap_signing

```sh
[bundle exec] fastlane ios bootstrap_signing
```

Create the first release certificate and exact App Store profiles

### ios create_version

```sh
[bundle exec] fastlane ios create_version
```

Create the target version on the existing app only

### ios upload_build

```sh
[bundle exec] fastlane ios upload_build
```

Upload one already-built IPA; never submit or release

### ios upload_metadata

```sh
[bundle exec] fastlane ios upload_metadata
```

Upload canonical metadata only; never submit or release

### ios upload_review_information

```sh
[bundle exec] fastlane ios upload_review_information
```

Upload reviewer contact, demo credentials and notes from external secrets

### ios review_information_check

```sh
[bundle exec] fastlane ios review_information_check
```

Read-only reviewer-contact and demo-account audit against the canonical manifest

### ios upload_privacy_urls

```sh
[bundle exec] fastlane ios upload_privacy_urls
```

Upload the two privacy URLs not fully covered by deliver metadata

### ios listing_check

```sh
[bundle exec] fastlane ios listing_check
```

Read-only App Store listing, privacy URL and screenshot audit

### ios compliance_check

```sh
[bundle exec] fastlane ios compliance_check
```

Read-only category, age-rating, content-rights and availability audit

### ios upload_store_classification

```sh
[bundle exec] fastlane ios upload_store_classification
```

Upload canonical age-rating answers after preserving inherited classification fields

### ios deduplicate_screenshots

```sh
[bundle exec] fastlane ios deduplicate_screenshots
```

Delete retry-created screenshot duplicates only

### ios replace_screenshots

```sh
[bundle exec] fastlane ios replace_screenshots
```

Exactly gated replacement of all screenshots for the editable target version;
never submits or releases the app

### ios select_build

```sh
[bundle exec] fastlane ios select_build
```

Select exactly one processed target build; never submit or release

### ios build_check

```sh
[bundle exec] fastlane ios build_check
```

Read-only status of the exact target build

### ios cancel_review_submission

```sh
[bundle exec] fastlane ios cancel_review_submission
```

Cancel only the in-progress review submission for the exact target version

### ios submission_check

```sh
[bundle exec] fastlane ios submission_check
```

Read-only submission completeness summary

### ios submit_for_review

```sh
[bundle exec] fastlane ios submit_for_review
```

Explicitly gated submission with automatic release after Apple approval

----

This README.md is auto-generated and will be re-generated every time [_fastlane_](https://fastlane.tools) is run.

More information about _fastlane_ can be found on [fastlane.tools](https://fastlane.tools).

The documentation of _fastlane_ can be found on [docs.fastlane.tools](https://docs.fastlane.tools).
