#!/bin/bash
set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" >/dev/null 2>&1 && pwd)"
if ! command -v bundle >/dev/null 2>&1; then
  echo "Bundler is required. Install it with the repository-approved Ruby package manager."
  exit 1
fi
if [ -z "${FESTAPP_RELEASE_MANIFEST:-}" ]; then
  echo "Set FESTAPP_RELEASE_MANIFEST to the private release config.json."
  exit 1
fi
if [ ! -f "$SCRIPT_DIR/fastlane/Fastfile" ] || [ ! -f "$FESTAPP_RELEASE_MANIFEST" ]; then
  echo "Canonical Fastfile or cutover manifest is missing."
  exit 1
fi
if ! (cd "$SCRIPT_DIR/fastlane" && bundle check >/dev/null); then
  echo "Pinned Fastlane dependencies are missing. Run bundle install in $SCRIPT_DIR/fastlane."
  exit 1
fi
fastlane_version="$(cd "$SCRIPT_DIR/fastlane" && bundle exec ruby -e 'require "fastlane/version"; print Fastlane::VERSION')"
echo "Canonical gated Fastlane $fastlane_version configuration is present."
