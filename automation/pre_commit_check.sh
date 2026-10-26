#!/bin/bash
# ==============================================================================
# PRE-COMMIT CHECK
# Purpose: Orchestrates pre-commit verification steps:
#          1. Syncs version number between Flutter and Web Client
#          2. Unifies translation files
#          3. Applies project configuration (calls apply_config.sh)
# Usage: ./automation/pre_commit_check.sh
# ==============================================================================

# Exit on error
set -e

# Get the absolute path to the directory containing this script
SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"
WEB_CLIENT_SCRIPTS="$PROJECT_ROOT/web_client/scripts"

echo "=================================================="
echo "PREPARING COMMIT: Syncing Version and Translations"
echo "=================================================="

# 0. Auto-increment Version
echo ""
echo ">>> Checking/Incrementing Version..."
if [ -f "$PROJECT_ROOT/automation/increment_version.js" ]; then
    node "$PROJECT_ROOT/automation/increment_version.js"
else
    echo "Warning: automation/increment_version.js not found."
fi

# 1. Sync Application Version (Handled by apply_config.sh now)
# echo ""
# echo ">>> Syncing Version..."
# Logic moved to automation/apply_config.sh via configure_version.js

# 2. Unify Translations (Flutter <-> Web Client)
echo ""
echo ">>> Unifying Translations..."
if [ -f "$WEB_CLIENT_SCRIPTS/unify_translations.js" ]; then
    node "$WEB_CLIENT_SCRIPTS/unify_translations.js"
else
    echo "Error: unify_translations.js not found at $WEB_CLIENT_SCRIPTS/unify_translations.js"
    exit 1
fi

# 3. Auto-configure Domain (based on branch)
echo ""
echo ">>> Checking Channel Configuration..."
CURRENT_BRANCH=$(git branch --show-current)

# 3. Apply Project Configuration (Universal Config)
echo ""
echo ">>> Applying Project Configuration..."

# The configure_project.sh script will read from scripts/project.conf

# The apply_config.sh script will read from automation/project.conf
if [ -f "$SCRIPT_DIR/apply_config.sh" ]; then
    "$SCRIPT_DIR/apply_config.sh"
else
    echo "Error: automation/apply_config.sh not found."
    exit 1
fi

echo ""
echo "=================================================="
echo "SUCCESS: Ready for commit!"
echo "=================================================="
