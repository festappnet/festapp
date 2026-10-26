#!/bin/bash
set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" >/dev/null 2>&1 && pwd)"
SIGNING_DIR="${FESTAPP_IOS_SIGNING_DIR:-$SCRIPT_DIR/signing}"
case "$SIGNING_DIR" in
  /*) ;;
  *) echo "FESTAPP_IOS_SIGNING_DIR must be an absolute path."; exit 1 ;;
esac
KEYCHAIN_PATH="$SIGNING_DIR/festapp-release.keychain-db"
PASSWORD_FILE="$SIGNING_DIR/keychain-password"

private_keys=("$SIGNING_DIR"/*.p12)
certificates=("$SIGNING_DIR"/*.cer)
if [ "${#private_keys[@]}" -ne 1 ] || [ ! -f "${private_keys[0]}" ]; then
  echo "Expected exactly one local distribution private key in $SIGNING_DIR."
  exit 1
fi
if [ "${#certificates[@]}" -ne 1 ] || [ ! -f "${certificates[0]}" ]; then
  echo "Expected exactly one local distribution certificate in $SIGNING_DIR."
  exit 1
fi

if [ ! -f "$PASSWORD_FILE" ]; then
  umask 077
  openssl rand -hex 32 > "$PASSWORD_FILE"
fi
chmod 600 "$PASSWORD_FILE"
keychain_password="$(<"$PASSWORD_FILE")"

if [ ! -f "$KEYCHAIN_PATH" ]; then
  security create-keychain -p "$keychain_password" "$KEYCHAIN_PATH"
fi
chmod 600 "$KEYCHAIN_PATH"
security unlock-keychain -p "$keychain_password" "$KEYCHAIN_PATH"
security set-keychain-settings -lut 21600 "$KEYCHAIN_PATH"

if ! security find-identity -v -p codesigning "$KEYCHAIN_PATH" | grep -q 'Apple Distribution:'; then
  security import "${private_keys[0]}" -k "$KEYCHAIN_PATH" -P '' -T /usr/bin/codesign -T /usr/bin/security >/dev/null
  if ! security find-identity -v -p codesigning "$KEYCHAIN_PATH" | grep -q 'Apple Distribution:'; then
    security import "${certificates[0]}" -k "$KEYCHAIN_PATH" -T /usr/bin/codesign -T /usr/bin/security >/dev/null
  fi
  security set-key-partition-list -S apple-tool:,apple: -s -k "$keychain_password" "$KEYCHAIN_PATH" >/dev/null
fi

existing_keychains=()
while IFS= read -r listed_keychain; do
  listed_keychain="${listed_keychain//\"/}"
  listed_keychain="${listed_keychain#${listed_keychain%%[![:space:]]*}}"
  if [ -n "$listed_keychain" ] && [ "$listed_keychain" != "$KEYCHAIN_PATH" ]; then
    existing_keychains+=("$listed_keychain")
  fi
done < <(security list-keychains -d user)
security list-keychains -d user -s "$KEYCHAIN_PATH" "${existing_keychains[@]}"

identity_count="$(security find-identity -v -p codesigning "$KEYCHAIN_PATH" | awk '/valid identities found/{print $1}')"
if [ "$identity_count" != "1" ]; then
  echo "Expected exactly one valid release signing identity in the dedicated keychain."
  exit 1
fi
echo "Dedicated release signing keychain is ready."
