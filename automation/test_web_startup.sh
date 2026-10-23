#!/usr/bin/env bash
# Restricted Android WebViews, startup recovery and production module identity.
# Uses mocked backend data only; never creates production orders.
set -euo pipefail
PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$PROJECT_ROOT/web_client"
node --test \
  tests/core/browser_storage.test.js \
  tests/core/backend_activation_service.test.js \
  tests/core/supabase_client_config.test.js \
  tests/core/web_client_bootstrap.test.js \
  tests/core/pwa_client_adapter.test.js \
  tests/core/flutter_runtime_handoff.test.js \
  tests/core/auth_bridge.test.js \
  tests/core/public_translations.test.js \
  tests/core/release_entry.test.js \
  tests/core/marketing_account.test.js \
  tests/components/user_header_initial_context.test.js \
  tests/components/user_header_auth_refresh.test.js \
  tests/components/db_orders_command_identity.test.js \
  tests/components/user_header_create_event.test.js \
  tests/components/user_header_admin_navigation.test.js \
  tests/components/blueprint_selector_v2.test.js \
  tests/components/blueprint_escape.test.js \
  tests/forms/form_loading.test.js \
  tests/forms/order_editor_button_lifecycle.test.js \
  tests/core/google_auth_service.test.js

# Real Chromium must see the form and account actions, including hidden ancestors.
node scripts/test_form_access_browser.mjs
