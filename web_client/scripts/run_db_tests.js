import pg from 'pg';
const { Client } = pg;
import fs from 'fs';
import path from 'path';
import { globSync } from 'glob';
import { fileURLToPath } from 'url';
import { assertLocalDatabaseUrl, assertDisposableDatabase } from '../tests/database/disposable_database.js';

const __filename = fileURLToPath(import.meta.url);
const __dirname = path.dirname(__filename);

// Default location for assertions helper
const PROJECT_ROOT = path.resolve(__dirname, '../../');
const ASSERTIONS_FILE = path.join(PROJECT_ROOT, 'database/tests/helpers/assertions.sql');
const TESTS_DIR = path.join(PROJECT_ROOT, 'database/tests');

// Load environment variables if .env.local exists (for local running)
const envLocalPath = path.join(PROJECT_ROOT, '.env.local');
if (fs.existsSync(envLocalPath)) {
  const envConfig = fs.readFileSync(envLocalPath, 'utf8');
  envConfig.split('\n').forEach((line) => {
    const [key, val] = line.split('=');
    if (key && val && !process.env[key]) {
      process.env[key.trim()] = val.trim();
    }
  });
}

const DATABASE_URL = process.env.DATABASE_URL;

if (!DATABASE_URL) {
  console.error('ERROR: DATABASE_URL environment variable is required.');
  console.error('   Set it in .env.local or pass it directly.');
  process.exit(1);
}

assertLocalDatabaseUrl(DATABASE_URL);

// Filter tests based on CLI arguments
const args = process.argv.slice(2);
const filters = args.filter(arg => !arg.startsWith('-'));

const allTestFiles = globSync(path.join(TESTS_DIR, '**/*_test.sql'));
const testFiles = allTestFiles.filter((file) => {
  if (filters.length === 0) return true;
  return filters.some(filter => file.includes(filter));
});

if (testFiles.length === 0) {
  console.log("No test files found matching criteria.");
  process.exit(0);
}

console.log(`Found ${testFiles.length} test file(s) to execute.`);

// Server deadlines cancel blocked SQL; the slightly longer client deadline also
// bounds network stalls. Apply them to setup and retries as well as each test.
const clientOptions = {
  connectionString: DATABASE_URL,
  ssl: DATABASE_URL.includes('supabase.com') ? { rejectUnauthorized: false } : false,
  connectionTimeoutMillis: 5000,
  lock_timeout: 5000,
  statement_timeout: 30000,
  query_timeout: 35000,
};

async function runTest(file) {
  const client = new Client(clientOptions);

  const relativePath = path.relative(PROJECT_ROOT, file);
  const started = performance.now();
  console.log(`\n▶ Running: ${relativePath}`);

  try {
    await client.connect();
    
    // Listen for notices (RAISE NOTICE)
    client.on('notice', (msg) => console.log(`  [NOTICE] ${msg.message}`));

    // Start Transaction
    await client.query('BEGIN');

    // Sequences are now reset GLOBALLY at the start of the run (in runAll).
    // This optimization allows tests to run in parallel without locking/contention on sequences.
    
    // Inject Assertions

    // Inject Assertions
    if (fs.existsSync(ASSERTIONS_FILE)) {
        const assertionsSql = fs.readFileSync(ASSERTIONS_FILE, 'utf8');
        await client.query(assertionsSql);
    } else {
        console.warn("  WARNING: assertions.sql not found. Some tests may fail.");
    }

    if (relativePath.startsWith('database/tests/scanning/') || ['database/tests/eshop/stripe/admission_test.sql','database/tests/eshop/stripe/refund_decisions_test.sql'].includes(relativePath)) {
      await client.query(fs.readFileSync(path.join(TESTS_DIR, 'scanning/fixture.sql'), 'utf8'));
    }

    // Read and Execute Test File
    const testSql = fs.readFileSync(file, 'utf8');
    // Operational maintenance helpers may deliberately live in pg_temp. Load
    // their canonical source in this same connection, within the test rollback.
    for (const [, source] of testSql.matchAll(/^-- test-setup: (database\/[\w./-]+\.sql)$/gm)) {
      const setupPath = path.resolve(PROJECT_ROOT, source);
      if (!setupPath.startsWith(path.join(PROJECT_ROOT, 'database') + path.sep)) {
        throw new Error('SQL test setup must stay inside the repository database directory');
      }
      await client.query(fs.readFileSync(setupPath, 'utf8'));
    }
    await client.query(testSql);

    // Rollback (Always clean up)
    await client.query('ROLLBACK');
    console.log(`  ✔ PASSED (${Math.round(performance.now() - started)} ms): ${relativePath}`);
    return true;

  } catch (err) {
    // Attempt rollback regardless of error
    try { await client.query('ROLLBACK'); } catch (e) {}
    
    console.error(`  ❌ FAILED (${Math.round(performance.now() - started)} ms): ${relativePath}`);
    console.error(`  Error: ${err.message} (${relativePath})`);
    if (err.where) console.error(`  Context: ${err.where}`);
    if (err.detail) console.error(`  Detail: ${err.detail}`);
    // Check for PostgreSQL error codes (e.g. 23505)
    if (err.code) console.error(`  Code: ${err.code}`);
    
    return false;
  } finally {
    await client.end();
  }
}

// Basic concurrency limit
const CONCURRENCY = 5;

async function runAll() {
  console.log('>>> Setup: Resetting Sequences (Global)...');
  // 1. Global Setup (Run Once)
  const setupClient = new Client(clientOptions);

  try {
    await setupClient.connect();
    await assertDisposableDatabase(setupClient);
    await resetSequences(setupClient);
  } catch (err) {
    console.error(`Setup Failed: ${err.message}`);
    process.exit(1);
  } finally {
    await setupClient.end();
  }
  console.log('>>> Setup Complete.\n');

  // 2. Run Tests in Batches (parallel)
  let successCount = 0;
  const failedFiles = [];

  // Helper to chunk array
  const chunk = (arr, size) => Array.from({ length: Math.ceil(arr.length / size) }, (v, i) =>
    arr.slice(i * size, i * size + size)
  );

  const batches = chunk(testFiles, CONCURRENCY);

  for (const batch of batches) {
    const results = await Promise.all(batch.map(async (file) => ({ file, success: await runTest(file) })));
    for (const { file, success } of results) {
      if (success) successCount++;
      else failedFiles.push(file);
    }
  }

  // 3. Retry failed tests sequentially — eliminates parallel-batching flakiness
  let recoveredCount = 0;
  const trulyFailedFiles = [];
  if (failedFiles.length > 0) {
    console.log('\n>>> Retrying ' + failedFiles.length + ' failed test(s) sequentially...');
    for (const file of failedFiles) {
      const success = await runTest(file);
      if (success) recoveredCount++;
      else trulyFailedFiles.push(file);
    }
  }

  const failureCount = trulyFailedFiles.length;
  successCount += recoveredCount;

  console.log('\n==================================================');
  console.log(`SUMMARY: ${successCount} Passed, ${failureCount} Failed` + (recoveredCount > 0 ? ` (recovered ${recoveredCount} on sequential retry)` : ''));
  if (trulyFailedFiles.length > 0) {
    console.log('Truly failing tests:');
    trulyFailedFiles.forEach(f => console.log('  - ' + path.relative(PROJECT_ROOT, f)));
  }
  console.log('==================================================');

  if (failureCount > 0) {
    process.exit(1);
  } else {
    process.exit(0);
  }
}



async function resetSequences(client) {
  await client.query(fs.readFileSync(path.join(TESTS_DIR, 'helpers/reset_owned_sequences.sql'), 'utf8'));
}

runAll();
