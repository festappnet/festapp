# 📦 iOS Release Upload Guide (App Store Connect)

This guide explains how to configure and use the `automation/release/`
automation to build, upload, and submit your Flutter iOS app to App Store
Connect.

---

## 🧷 Prerequisites

- macOS with Xcode installed
- Flutter installed and set up with FVM
- Fastlane installed (or let the script install it for you)
- Your project must be correctly signed with provisioning profiles

---

## 🔐 Step 1: Create an API Key for App Store Connect

1. Go to
   [https://appstoreconnect.apple.com/access/integrations/api](https://appstoreconnect.apple.com/access/integrations/api)
2. Click the ➕ button to create a new API key
3. Name it (e.g., `Release Upload Key`)
4. Set **Access**: **App Manager** or **Admin** (❗ required for submitting
   builds)
5. Download the `.p8` file (e.g. `AuthKey_ABCD123456.p8`)

---

## 🗝 Step 2: Provision credentials from the private configuration source

Provision the App Store Connect key and identifiers from the designated private
configuration repository into a local directory outside this repository. Do not
copy the `.p8` key into the Festapp checkout.

Create the ignored local file `automation/release/.set_appstore_env.sh` with
references to the externally provisioned values:

```bash
export APP_STORE_CONNECT_KEY_ID="ABCD123456"
export APP_STORE_CONNECT_ISSUER_ID="01234567-89ab-cdef-0123-456789abcdef"
export APP_STORE_CONNECT_KEY_PATH="<private-config-root>/AuthKey_ABCD123456.p8"
```

The key file must be readable only by its owner (`chmod 600`). Both the shell
script and release tooling reject missing or unsafe key material, and the
release tooling rejects any key path inside the Festapp repository.

---

## 📁 Step 3: Verify the External Private Key

Confirm that the configured path resolves outside the Festapp checkout:

```bash
source automation/release/.set_appstore_env.sh
test -f "$APP_STORE_CONNECT_KEY_PATH"
```

---

## ⚙️ Step 4: Initialize Fastlane (only once)

Run the setup script to install Fastlane (if needed) and create `Fastfile`:

```bash
./automation/release/fastlane_setup.sh
```

---

## 🚀 Step 5: Build, Upload & Submit

```bash
source automation/release/.set_appstore_env.sh
./automation/release/ios_build_and_upload.sh
```

You’ll be prompted to enter **release notes**. The script will:

1. Build the IPA with FVM
2. Extract the app name from `Info.plist`
3. Locate or select the `.ipa` file
4. Upload the build
5. Submit it for review via Fastlane

---

## 📝 How to Customize the Release Message

You’ll be prompted like this:

```
📝 Enter release notes (press ENTER to finish):
```

Whatever you type will be used as the "What's New" description for that version.

---

## 📌 Troubleshooting

### "Private key not found"

Make sure:

- the private configuration source has provisioned the original `.p8` file outside this repository
- `APP_STORE_CONNECT_KEY_PATH` is an absolute path to that external file
- the key file mode is `600`
- the key ID in your env file matches the provisioned key

---

## ✅ Example Folder Structure

```
my_project/
├── ios/
│   └── Runner/
│       └── Info.plist
├── automation/
│   └── release/
│       ├── ios_build_and_upload.sh
│       ├── fastlane_setup.sh
│       ├── .set_appstore_env.sh
│       ├── ios_howto.md
│       └── fastlane/
│           └── Fastfile
└── pubspec.yaml
```

The provisioned `AuthKey_ABCD123456.p8` is deliberately outside this tree.

---
