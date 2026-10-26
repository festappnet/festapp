/**
 * Integration test runner for surcharge feature.
 * Deploys all surcharge-related SQL functions before running each test,
 * ensuring tests run against the latest function versions.
 *
 * Usage: node web_client/scripts/run_integration_tests.js [test_file_pattern]
 * Example: node web_client/scripts/run_integration_tests.js full_deposit_flow
 */

import pg from 'pg';
const { Client } = pg;
import fs from 'fs';
import path from 'path';
import { globSync } from 'glob';
import { fileURLToPath } from 'url';

const __filename = fileURLToPath(import.meta.url);
const __dirname = path.dirname(__filename);

const PROJECT_ROOT = path.resolve(__dirname, '../../');
const ASSERTIONS_FILE = path.join(PROJECT_ROOT, 'database/tests/helpers/assertions.sql');
const INTEGRATION_DIR = path.join(PROJECT_ROOT, 'database/tests/eshop/integration');

// Function files to deploy before each integration test (order matters for dependencies)
const FUNCTION_FILES = [
  'database/functions/eshop_orders/update_order_and_tickets_to_paid.sql',
  'database/functions/eshop_orders/recalculate_order_payment_status.sql',
  'database/functions/eshop_transactions/apply_transaction_pairing.sql',
  'database/functions/emails/queue_payment_reminders.sql',
  'database/functions/emails/get_due_queue_emails.sql',
  'database/functions/eshop_orders/scan_ticket.sql',
  'database/functions/eshop/create_ticket_order.sql',
  'database/functions/eshop/get_report_for_occasion.sql',
].map(f => path.join(PROJECT_ROOT, f));

// Load environment variables
const envLocalPath = path.join(PROJECT_ROOT, '.env.local');
if (fs.existsSync(envLocalPath)) {
  const envConfig = fs.readFileSync(envLocalPath, 'utf8');
  envConfig.split('\n').forEach((line) => {
    const idx = line.indexOf('=');
    if (idx > 0) {
      const key = line.substring(0, idx).trim();
      const val = line.substring(idx + 1).trim();
      if (key && val && !process.env[key]) process.env[key] = val;
    }
  });
}

const DATABASE_URL = process.env.DATABASE_URL;
if (!DATABASE_URL) {
  console.error("Error: DATABASE_URL is not set.");
  process.exit(1);
}

// Filter tests
const args = process.argv.slice(2);
const filters = args.filter(arg => !arg.startsWith('-'));

const allTestFiles = globSync(path.join(INTEGRATION_DIR, '*_test.sql'));
const testFiles = allTestFiles.filter((file) => {
  if (filters.length === 0) return true;
  return filters.some(filter => file.includes(filter));
});

if (testFiles.length === 0) {
  console.log("No integration test files found matching criteria.");
  process.exit(0);
}

console.log(`Found ${testFiles.length} integration test file(s).`);
console.log(`Will deploy ${FUNCTION_FILES.length} function(s) before each test.\n`);

// Read all function SQL files once
const functionSqls = FUNCTION_FILES.map(f => {
  if (!fs.existsSync(f)) {
    console.error(`Function file not found: ${f}`);
    process.exit(1);
  }
  return fs.readFileSync(f, 'utf8');
});

async function runTest(file) {
  const client = new Client({
    connectionString: DATABASE_URL,
    ssl: DATABASE_URL.includes('supabase.com') ? { rejectUnauthorized: false } : false
  });

  const relativePath = path.relative(PROJECT_ROOT, file);
  console.log(`\u25b6 Running: ${relativePath}`);

  try {
    await client.connect();
    client.on('notice', (msg) => console.log(`  [NOTICE] ${msg.message}`));

    // Start transaction
    await client.query('BEGIN');

    // Inject assertions
    if (fs.existsSync(ASSERTIONS_FILE)) {
      const assertionsSql = fs.readFileSync(ASSERTIONS_FILE, 'utf8');
      await client.query(assertionsSql);
    }

    // Deploy surcharge functions
    for (const sql of functionSqls) {
      await client.query(sql);
    }

    // Run the test
    const testSql = fs.readFileSync(file, 'utf8');
    await client.query(testSql);

    // Rollback
    await client.query('ROLLBACK');
    console.log(`  \u2714 PASSED`);
    return true;

  } catch (err) {
    try { await client.query('ROLLBACK'); } catch (e) {}
    console.error(`  \u274c FAILED`);
    console.error(`  Error: ${err.message}`);
    if (err.code) console.error(`  Code: ${err.code}`);
    return false;
  } finally {
    await client.end();
  }
}

async function runAll() {
  let successCount = 0;
  let failureCount = 0;

  for (const file of testFiles) {
    const success = await runTest(file);
    if (success) successCount++;
    else failureCount++;
  }

  console.log('\n==================================================');
  console.log(`SUMMARY: ${successCount} Passed, ${failureCount} Failed`);
  console.log('==================================================');

  process.exit(failureCount > 0 ? 1 : 0);
}

runAll();
