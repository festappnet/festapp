#!/bin/bash
# ==============================================================================
# TEST ALL
# Purpose: Runs all tests for the project.
#
# Reads credentials from .env.local (DATABASE_URL, SUPABASE_URL, etc.)
# Tests that require missing env vars are skipped gracefully.
#
# Test types:
# - Web client (JavaScript): npm test
# - Database (SQL): node web_client/scripts/run_db_tests.js
# - Deno edge functions: deno test
# - Flutter: fvm flutter test
#
# Usage: ./automation/test_all.sh [web] [db] [flutter] [integration]
# ==============================================================================

# Exit on error
set -e

# Get the absolute path to the directory containing this script
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

# Use the isolated schema-baseline database when it is already running and no
# explicit database target was supplied. Never start or rebuild it implicitly.
if [ -z "${DATABASE_URL-}" ] && command -v pg_isready >/dev/null 2>&1 \
    && pg_isready -h 127.0.0.1 -p 55432 -d postgres >/dev/null 2>&1; then
    export DATABASE_URL="postgresql://postgres:postgres@127.0.0.1:55432/postgres?sslmode=disable"
fi

echo "========================================"
if [ -n "$DATABASE_URL" ]; then
    echo "Database: ${DATABASE_URL:0:50}..."
else
    echo "WARNING: DATABASE_URL not set — DB tests will be skipped."
fi
if [ -n "$SUPABASE_URL" ]; then
    echo "Supabase: ${SUPABASE_URL}"
else
    echo "WARNING: SUPABASE_URL not set — integration tests will be skipped."
fi
echo "========================================"
echo ""

WEB_CLIENT_DIR="$PROJECT_ROOT/web_client"

echo "=================================================="
echo "RUNNING TESTS"
echo "=================================================="

# Default to all false if args provided, else all true
RUN_WEB=false
RUN_DB=false
RUN_FLUTTER=false
RUN_INTEGRATION=false
RUN_AUTOMATION=false

# If no arguments, run all
if [ $# -eq 0 ]; then
    RUN_WEB=true
    RUN_DB=true
    RUN_FLUTTER=true
    RUN_INTEGRATION=true
    RUN_AUTOMATION=true
else
    # Parse arguments
    for arg in "$@"
    do
        case $arg in
            web)
                RUN_WEB=true
                ;;
            db)
                RUN_DB=true
                ;;
            flutter)
                RUN_FLUTTER=true
                ;;
            integration)
                RUN_INTEGRATION=true
                ;;
            automation)
                RUN_AUTOMATION=true
                ;;
            *)
                echo "Unknown argument: $arg"
                echo "Usage: ./automation/test_all.sh [web] [db] [flutter] [integration] [automation]"
                exit 1
                ;;
        esac
    done
fi

# Function to run command with timeout (Mac compatible)
run_with_timeout() {
    local timeout=$1
    shift
    local cmd="$@"
    
    echo "Running with timeout ${timeout}s: $cmd"
    
    # Start command in background
    eval "$cmd" &
    local pid=$!
    
    local count=0
    while kill -0 $pid 2>/dev/null; do
        if [ $count -ge $timeout ]; then
            echo ""
            echo "❌ CANCELLING: Command timed out after ${timeout} seconds."
            kill -9 $pid
            wait $pid 2>/dev/null
            return 1
        fi
        sleep 1
        count=$((count+1))
    done
    
    wait $pid
    return $?
}

# 1. Run Web Client Tests
if [ "$RUN_WEB" = true ]; then
    echo ""
    echo ">>> Web Client Tests..."
    if [ -d "$WEB_CLIENT_DIR" ]; then
        cd "$WEB_CLIENT_DIR"
        # Run npm test with 60s timeout (increased for stability)
        set +e
        run_with_timeout 60 "npm test"
        res=$?
        set -e
        
        if [ $res -ne 0 ]; then
            echo "⚠️  WARNING: Web Client Tests Failed or Timed Out."
        fi
    else
        echo "Error: web_client directory not found at $WEB_CLIENT_DIR"
    fi
fi

# 2. Run Database Tests
if [ "$RUN_DB" = true ]; then
    echo ""
    echo ">>> Database Tests..."

    if [ -z "$DATABASE_URL" ]; then
        echo "SKIPPING: DATABASE_URL not set."
    else
        DB_TEST_RUNNER="$PROJECT_ROOT/web_client/scripts/run_db_tests.js"
        if [ -f "$DB_TEST_RUNNER" ]; then
            node "$DB_TEST_RUNNER"
        else
            echo "WARNING: DB Test Runner not found at $DB_TEST_RUNNER. Skipping."
        fi
    fi
fi

# 3. Run Flutter Tests
if [ "$RUN_FLUTTER" = true ]; then
    echo ""
    echo ">>> Flutter Tests..."
    cd "$PROJECT_ROOT"
    
    # Check if fvm is installed/used
    if command -v fvm &> /dev/null; then
        FLUTTER_CMD="fvm flutter"
    else
        FLUTTER_CMD="flutter"
    fi
    
    set +e
    $FLUTTER_CMD test
    res=$?
    set -e
    
    if [ $res -ne 0 ]; then
        echo "⚠️  WARNING: Flutter Tests Failed."
    fi
fi

# 3b. Run Deno Edge Function Tests
if [ "$RUN_DB" = true ] || [ "$RUN_INTEGRATION" = true ]; then
    # Deno Edge Function Tests
    # Tests business logic of server functions.
    echo ""
    echo ">>> Deno Edge Function Tests..."
    
    if command -v deno &> /dev/null; then
        # Find and run all test_*.ts files in supabase/functions
        # We use explicit paths to avoid running unrelated stuff if any
        DENO_TEST_FILES=$(find supabase/functions -name "test_*.ts" -not -path "*/node_modules/*")
        
        if [ -n "$DENO_TEST_FILES" ]; then
             echo "Found Deno tests: $DENO_TEST_FILES"
             # Run without --allow-all to be safe.
             # test_parser_comprehensive only needs logic, but imports might trigger env read.
             set +e
             deno test --allow-env --allow-net --allow-read $DENO_TEST_FILES
             res=$?
             set -e
             
             if [ $res -ne 0 ]; then
                echo "⚠️  WARNING: Deno Tests Failed."
                exit 1 
             fi
        else
             echo "No Deno tests found."
        fi
    else
        echo "⚠️  Deno not installed. Skipping Edge Function tests."
    fi
fi

# 4. Run Integration Tests
if [ "$RUN_INTEGRATION" = true ]; then
    echo ""
    echo ">>> Integration Tests..."

    # All integration tests (bank import, image worker) via Vitest
    WORKER_TEST_DIR="$PROJECT_ROOT/workers/image-worker"
    if [ -d "$WORKER_TEST_DIR" ] && [ -n "$DATABASE_URL" ]; then
        echo "Running Integration Tests (Vitest)..."
        cd "$WORKER_TEST_DIR"
        set +e
        npx vitest run tests/integration/ 2>&1
        res=$?
        set -e
        cd "$PROJECT_ROOT"
        if [ $res -ne 0 ]; then
            echo "⚠️  WARNING: Integration Tests Failed."
        fi
    else
        echo "⚠️  SKIPPING Integration Tests: Missing DATABASE_URL."
    fi
fi

# 5. Run Automation Tests (direct deploy contract, apply_config.sh smoke).
if [ "$RUN_AUTOMATION" = true ]; then
    echo ""
    echo ">>> Automation Scripts Tests..."

    for t in "$SCRIPT_DIR/tests/apply_config.test.sh" "$SCRIPT_DIR/tests/legal_config.test.sh" "$SCRIPT_DIR/tests/deploy_direct.test.sh" "$SCRIPT_DIR/tests/deploy_workflow.test.sh" "$SCRIPT_DIR/tests/migration_layout.test.sh" "$SCRIPT_DIR/tests/hetzner_supabase_rehearsal_schema.test.sh" "$SCRIPT_DIR/tests/update_prompt.test.sh" "$SCRIPT_DIR/tests/update_prompt_behavior.test.mjs" "$SCRIPT_DIR/tests/flutter_bootstrap_guard.test.mjs" "$SCRIPT_DIR/tests/client_sync_cutover.test.mjs" "$SCRIPT_DIR/tests/pwa_offline.test.mjs" "$SCRIPT_DIR/tests/project_version.test.mjs"; do
        if [ -x "$t" ]; then
            echo "Running $(basename "$t")..."
            set +e
            "$t"
            res=$?
            set -e
            if [ $res -ne 0 ]; then
                echo "⚠️  WARNING: $(basename "$t") FAILED."
                exit 1
            fi
        else
            echo "Skipping $t (missing or not executable)."
        fi
    done

    echo "Running canonical PWA storage and recovery contract tests..."
    node --test \
      "$SCRIPT_DIR/tests/pwa_manifest.test.mjs" \
      "$SCRIPT_DIR/tests/pwa_reconcile.test.mjs" \
      "$SCRIPT_DIR/tests/pwa_storage_bridge.test.mjs" \
      "$SCRIPT_DIR/tests/cloudflare_pages_project.test.mjs" \
      "$SCRIPT_DIR/tests/hetzner_supabase_infrastructure.test.mjs" \
      "$SCRIPT_DIR/tests/hetzner_supabase_inventory.test.mjs" \
      "$SCRIPT_DIR/tests/hetzner_supabase_cutover_mode_gate.test.mjs" \
      "$SCRIPT_DIR/tests/hetzner_supabase_operational_readiness.test.mjs" \
      "$SCRIPT_DIR/tests/hetzner_supabase_production_promotion.test.mjs" \
      "$SCRIPT_DIR/tests/supabase_client_config.test.mjs" \
      "$SCRIPT_DIR/tests/client_rpc_contract.test.mjs" \
      "$SCRIPT_DIR/tests/client_backend_surface.test.mjs" \
      "$SCRIPT_DIR/hetzner-supabase/runtime/verify-pins.mjs" \
      "$SCRIPT_DIR/tests/private_inputs_schema.test.mjs" \
      "$SCRIPT_DIR/tests/recovery_readiness.test.mjs" \
      "$WEB_CLIENT_DIR/tests/core/pwa_client_adapter.test.js"
fi

echo ""
echo "=================================================="
echo "Done."
echo "=================================================="
