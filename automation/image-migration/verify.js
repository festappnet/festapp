#!/usr/bin/env node

/**
 * Post-migration verification script.
 *
 * Checks:
 *   1. Zero remaining Supabase Storage URLs across all 18 database columns
 *   2. File count parity between Supabase Storage and R2 (if credentials available)
 *   3. Dual-write rollback period status
 *
 * Usage:
 *   node verify.js
 *
 * Requires: DATABASE_URL environment variable
 * Optional: SUPABASE_URL, SUPABASE_SERVICE_ROLE_KEY, CF_ACCOUNT_ID,
 *           R2_ACCESS_KEY_ID, R2_SECRET_ACCESS_KEY, R2_BUCKET_NAME
 *
 * Exit code: 0 if all checks pass, 1 if any fail
 */

import { config } from 'dotenv';
import { createPool, closePool } from './lib/db.js';
import { createClient } from '@supabase/supabase-js';
import { createR2Client, countR2Objects } from './lib/r2-client.js';
import { listAllFiles } from './lib/supabase-storage.js';

config();

/** This project's Supabase instance (from .env) */
const THIS_PROJECT = process.env.SUPABASE_PROJECT_REF;
if (!THIS_PROJECT) {
  console.error('ERROR: SUPABASE_PROJECT_REF is required in .env');
  process.exit(1);
}
const THIS_PROJECT_PATTERN = `%${THIS_PROJECT}%supabase.co/storage%`;
const ALL_SUPABASE_PATTERN = '%supabase.co/storage%';

// ─── Category 1: Database URL Scan ───────────────────────────────

/** Build the scan query. Same structure for both project-scoped and global scans. */
function buildScanQuery() {
  return `
    SELECT 'images.link' AS location, COUNT(*) AS remaining
    FROM images WHERE link LIKE $1
    UNION ALL
    SELECT 'icons.link', COUNT(*)
    FROM icons WHERE link LIKE $1
    UNION ALL
    SELECT 'occasions.data.image', COUNT(*)
    FROM occasions WHERE data->>'image' LIKE $1
    UNION ALL
    SELECT 'occasions.data.email_banner', COUNT(*)
    FROM occasions WHERE data->>'email_banner' LIKE $1
    UNION ALL
    SELECT 'occasions.data.logo', COUNT(*)
    FROM occasions WHERE data->>'logo' LIKE $1
    UNION ALL
    SELECT 'occasions.data.map_layer.layer_link', COUNT(*)
    FROM occasions WHERE data->'map_layer'->>'layer_link' LIKE $1
    UNION ALL
    SELECT 'occasions.data.map_layer.logo', COUNT(*)
    FROM occasions WHERE data->'map_layer'->>'logo' LIKE $1
    UNION ALL
    SELECT 'occasions.features', COUNT(*)
    FROM occasions WHERE features IS NOT NULL AND features::TEXT LIKE $1
    UNION ALL
    SELECT 'units.data (all keys)', COUNT(*)
    FROM units WHERE data IS NOT NULL AND data::TEXT LIKE $1
    UNION ALL
    SELECT 'organizations.data.email_banner', COUNT(*)
    FROM organizations WHERE data->>'email_banner' LIKE $1
    UNION ALL
    SELECT 'information.description', COUNT(*)
    FROM information WHERE description LIKE $1
    UNION ALL
    SELECT 'events.description', COUNT(*)
    FROM events WHERE description LIKE $1
    UNION ALL
    SELECT 'news.message', COUNT(*)
    FROM news WHERE message LIKE $1
    UNION ALL
    SELECT 'places.description', COUNT(*)
    FROM places WHERE description LIKE $1
    UNION ALL
    SELECT 'user_group_info.description', COUNT(*)
    FROM user_group_info WHERE description LIKE $1
    UNION ALL
    SELECT 'email_wrappers.html', COUNT(*)
    FROM email_wrappers WHERE html LIKE $1
    UNION ALL
    SELECT 'email_templates.html', COUNT(*)
    FROM email_templates WHERE html LIKE $1
    UNION ALL
    SELECT 'forms.header', COUNT(*)
    FROM forms WHERE header LIKE $1
    UNION ALL
    SELECT 'forms.header_off', COUNT(*)
    FROM forms WHERE header_off LIKE $1
  `;
}

async function scanDatabaseUrls(pool) {
  console.log('=== Category 1: Database URL Scan ===\n');

  const query = buildScanQuery();

  // Scan for this project specifically
  const { rows } = await pool.query(query, [THIS_PROJECT_PATTERN]);

  let totalRemaining = 0;
  let failedColumns = [];

  console.log('  Column                                Remaining');
  console.log('  ──────────────────────────────────────────────────');

  for (const row of rows) {
    const count = parseInt(row.remaining, 10);
    const status = count === 0 ? 'PASS' : 'FAIL';
    const marker = count === 0 ? '  ' : '!!';
    console.log(`  ${marker} ${row.location.padEnd(40)} ${count} ${status !== 'PASS' ? '  <-- FAIL' : ''}`);
    totalRemaining += count;
    if (count > 0) {
      failedColumns.push({ location: row.location, count });
    }
  }

  console.log('  ──────────────────────────────────────────────────');
  console.log(`  Total remaining Supabase URLs: ${totalRemaining}`);
  console.log(`  Columns scanned: ${rows.length}`);
  console.log(`  Status: ${totalRemaining === 0 ? 'PASS' : 'FAIL'}\n`);

  // Also scan for other Supabase projects (informational, not a failure)
  const { rows: allRows } = await pool.query(query, [ALL_SUPABASE_PATTERN]);
  let otherProjectCount = 0;
  for (const row of allRows) {
    otherProjectCount += parseInt(row.remaining, 10);
  }
  otherProjectCount -= totalRemaining; // subtract this project's count
  if (otherProjectCount > 0) {
    console.log(`  Note: ${otherProjectCount} URLs from OTHER Supabase projects remain (not an error)\n`);
  }

  return { passed: totalRemaining === 0, totalRemaining, columns: rows.length, failedColumns };
}

// ─── Category 2: File Count Parity ───────────────────────────────

async function checkFileParity() {
  console.log('=== Category 2: File Count Parity ===\n');

  const hasR2 = process.env.CF_ACCOUNT_ID && process.env.R2_ACCESS_KEY_ID && process.env.R2_SECRET_ACCESS_KEY;
  const hasSupabase = process.env.SUPABASE_URL && process.env.SUPABASE_SERVICE_ROLE_KEY;

  if (!hasR2 || !hasSupabase) {
    const missing = [];
    if (!hasR2) missing.push('R2 credentials (CF_ACCOUNT_ID, R2_ACCESS_KEY_ID, R2_SECRET_ACCESS_KEY)');
    if (!hasSupabase) missing.push('Supabase credentials (SUPABASE_URL, SUPABASE_SERVICE_ROLE_KEY)');
    console.log(`  SKIPPED: ${missing.join(' and ')} not configured`);
    console.log('  Set credentials in .env to enable file count parity check.\n');
    return { passed: true, skipped: true };
  }

  const r2Bucket = process.env.R2_BUCKET_NAME || 'festapp-images';
  const bucket = 'public-files';

  // Count R2 objects
  const r2 = createR2Client(process.env);
  const r2Result = await countR2Objects(r2, r2Bucket);

  // Count Supabase Storage files
  const supabase = createClient(process.env.SUPABASE_URL, process.env.SUPABASE_SERVICE_ROLE_KEY);
  const supabaseFiles = await listAllFiles(supabase, bucket);

  const match = supabaseFiles.length === r2Result.count;
  console.log(`  Supabase Storage: ${supabaseFiles.length} files`);
  console.log(`  Cloudflare R2:    ${r2Result.count} files`);
  console.log(`  Match: ${match}`);
  console.log(`  Status: ${match ? 'PASS' : 'FAIL'}\n`);

  return {
    passed: match,
    skipped: false,
    supabaseCount: supabaseFiles.length,
    r2Count: r2Result.count,
  };
}

// ─── Category 3: Dual-Write Status ──────────────────────────────

function printDualWriteStatus() {
  console.log('=== Category 3: Dual-Write Period Status ===\n');
  console.log('  DUAL-WRITE STATUS:');
  console.log('  - New uploads already go to R2 (Phase 3 complete)');
  console.log('  - Supabase Storage files MUST be retained for rollback');
  console.log('  - Do NOT delete Supabase Storage files for at least 30 days after URL rewrite');
  console.log('  - Rollback: reverse URL rewrite (REPLACE R2_PREFIX with SUPABASE_PREFIX)');
  console.log('');
}

// ─── Main ────────────────────────────────────────────────────────

async function main() {
  const databaseUrl = process.env.DATABASE_URL;
  if (!databaseUrl) {
    console.error('Missing required environment variable: DATABASE_URL');
    console.error('Set DATABASE_URL to your PostgreSQL connection string.');
    process.exit(1);
  }

  console.log(`\n=== Post-Migration Verification ===`);
  console.log(`Database: ${databaseUrl.replace(/:[^:@]+@/, ':***@')}\n`);

  const pool = createPool(databaseUrl);
  let allPassed = true;

  try {
    // Category 1: Database URL scan
    const dbResult = await scanDatabaseUrls(pool);
    if (!dbResult.passed) allPassed = false;

    // Category 2: File count parity
    const parityResult = await checkFileParity();
    if (!parityResult.passed) allPassed = false;

    // Category 3: Dual-write status (informational)
    printDualWriteStatus();

    // Summary
    console.log('=== VERIFICATION SUMMARY ===\n');
    console.log(`  Database URL scan:  ${dbResult.passed ? 'PASS' : 'FAIL'} (${dbResult.totalRemaining} Supabase URLs remaining across ${dbResult.columns} columns)`);

    if (parityResult.skipped) {
      console.log('  File count parity:  SKIPPED (credentials not configured)');
    } else {
      console.log(`  File count parity:  ${parityResult.passed ? 'PASS' : 'FAIL'} (Supabase=${parityResult.supabaseCount}, R2=${parityResult.r2Count})`);
    }

    console.log('  Dual-write period:  INFO (retain Supabase files for 30+ days)');
    console.log(`  Overall:            ${allPassed ? 'PASS' : 'FAIL'}\n`);

    if (!allPassed) {
      if (dbResult.failedColumns.length > 0) {
        console.log('  Failed columns:');
        for (const col of dbResult.failedColumns) {
          console.log(`    - ${col.location}: ${col.count} remaining`);
        }
        console.log('');
      }
      process.exit(1);
    }
  } finally {
    await closePool(pool);
  }
}

main().catch((err) => {
  console.error('Fatal error:', err.message);
  process.exit(1);
});
