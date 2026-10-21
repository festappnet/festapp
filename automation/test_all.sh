#!/bin/bash
# Broad selected-lane wrapper. Required prerequisites fail closed; optional test
# skips remain owned by their test runners. Lifecycle and receipts: test_all.py.
set -e
SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"

# Load defaults from .env.local without overriding explicit CI/shell values.
# This is especially important for DATABASE_URL: callers must be able to force
# tests onto a disposable local database even when .env.local points elsewhere.
cd "$PROJECT_ROOT"
if [ -f ".env.local" ]; then
    FESTAPP_DATABASE_URL_OVERRIDE="${DATABASE_URL-}"
    FESTAPP_SUPABASE_URL_OVERRIDE="${SUPABASE_URL-}"
    FESTAPP_SUPABASE_ANON_KEY_OVERRIDE="${SUPABASE_ANON_KEY-}"
    FESTAPP_SUPABASE_SERVICE_ROLE_KEY_OVERRIDE="${SUPABASE_SERVICE_ROLE_KEY-}"
    set -a
    source .env.local
    set +a
    [ -n "$FESTAPP_DATABASE_URL_OVERRIDE" ] && export DATABASE_URL="$FESTAPP_DATABASE_URL_OVERRIDE"
    [ -n "$FESTAPP_SUPABASE_URL_OVERRIDE" ] && export SUPABASE_URL="$FESTAPP_SUPABASE_URL_OVERRIDE"
    [ -n "$FESTAPP_SUPABASE_ANON_KEY_OVERRIDE" ] && export SUPABASE_ANON_KEY="$FESTAPP_SUPABASE_ANON_KEY_OVERRIDE"
    [ -n "$FESTAPP_SUPABASE_SERVICE_ROLE_KEY_OVERRIDE" ] && export SUPABASE_SERVICE_ROLE_KEY="$FESTAPP_SUPABASE_SERVICE_ROLE_KEY_OVERRIDE"
fi

exec python3 "$SCRIPT_DIR/test_all.py" "$@"
