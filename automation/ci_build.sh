#!/bin/bash
# ==============================================================================
# CI BUILD
# Purpose: specialized build script for CI/CD environments (e.g. Netlify/GitHub).
#          - Installs Flutter (if missing)
#          - Builds Flutter App (release)
#          - Builds Web Client
#          - Merges Web Client into Flutter build output
# Usage: ./automation/ci_build.sh
# ==============================================================================
set -euo pipefail

PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
bash "$PROJECT_ROOT/automation/build_web_bundle.sh" static
