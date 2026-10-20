#!/usr/bin/env node

/**
 * Migrate files from Supabase Storage to Cloudflare R2.
 *
 * Strategy:
 *   1. Query database for all distinct Supabase Storage URLs across all columns
 *   2. Download each file via public HTTP (no service role key needed)
 *   3. Upload to R2 via `wrangler r2 object put` (uses existing wrangler auth)
 *
 * Usage:
 *   node migrate-files.js --dry-run                # List files without uploading
 *   node migrate-files.js                          # Migrate all files
 *   node migrate-files.js --concurrency 5          # Parallel uploads (default: 3)
 */

import { config } from 'dotenv';
import { createPool, closePool } from './lib/db.js';
import { SUPABASE_STORAGE_PREFIX } from './lib/url-rewriter.js';
import pLimit from 'p-limit';
import { execFile } from 'node:child_process';
import { writeFile, unlink, mkdir } from 'node:fs/promises';
import { promisify } from 'node:util';
import { tmpdir } from 'node:os';
import { join } from 'node:path';

const execFileAsync = promisify(execFile);

config();

const MIME_TYPES = {
  '.jpg': 'image/jpeg',
  '.jpeg': 'image/jpeg',
  '.png': 'image/png',
  '.gif': 'image/gif',
  '.webp': 'image/webp',
  '.svg': 'image/svg+xml',
  '.pdf': 'application/pdf',
  '.ico': 'image/x-icon',
};

function getMimeType(filePath) {
  const ext = filePath.substring(filePath.lastIndexOf('.')).toLowerCase();
  return MIME_TYPES[ext] || 'application/octet-stream';
}

function parseArgs() {
  const args = process.argv.slice(2);
  const dryRun = args.includes('--dry-run');
  let concurrency = 3;
  const concIdx = args.indexOf('--concurrency');
  if (concIdx !== -1 && args[concIdx + 1]) {
    concurrency = parseInt(args[concIdx + 1], 10);
  }
  return { dryRun, concurrency };
}

/**
 * Query all distinct Supabase Storage URLs from the database.
 * Covers: plain text columns, JSONB fields, and HTML columns.
 */
async function collectAllSupabaseUrls(pool) {
  const SUPABASE_PATTERN = '%supabase.co/storage%';

  // Each query extracts URLs from different column types
  const queries = [
    // Plain text link columns
    `SELECT DISTINCT link AS url FROM images WHERE link LIKE $1`,
    `SELECT DISTINCT link AS url FROM icons WHERE link LIKE $1`,

    // JSONB data fields (occasions)
    `SELECT DISTINCT data->>'image' AS url FROM occasions WHERE data->>'image' LIKE $1`,
    `SELECT DISTINCT data->>'email_banner' AS url FROM occasions WHERE data->>'email_banner' LIKE $1`,
    `SELECT DISTINCT data->>'logo' AS url FROM occasions WHERE data->>'logo' LIKE $1`,
    `SELECT DISTINCT data->'map_layer'->>'layer_link' AS url FROM occasions WHERE data->'map_layer'->>'layer_link' LIKE $1`,
    `SELECT DISTINCT data->'map_layer'->>'logo' AS url FROM occasions WHERE data->'map_layer'->>'logo' LIKE $1`,

    // JSONB data fields (units, organizations)
    `SELECT DISTINCT data->>'email_banner' AS url FROM units WHERE data->>'email_banner' LIKE $1`,
    `SELECT DISTINCT data->>'email_banner' AS url FROM organizations WHERE data->>'email_banner' LIKE $1`,
  ];

  // HTML columns — extract URLs with regex in SQL
  const htmlColumns = [
    ['information', 'description'],
    ['events', 'description'],
    ['news', 'message'],
    ['places', 'description'],
    ['user_group_info', 'description'],
    ['email_wrappers', 'html'],
    ['email_templates', 'html'],
    ['forms', 'header'],
    ['forms', 'header_off'],
  ];

  // For HTML columns, we'll fetch the HTML and extract URLs in JS
  const htmlQueries = htmlColumns.map(
    ([table, col]) =>
      `SELECT DISTINCT "${col}" AS html FROM "${table}" WHERE "${col}" LIKE $1`
  );

  const urlSet = new Set();

  // Run plain/JSONB queries
  for (const query of queries) {
    try {
      const { rows } = await pool.query(query, [SUPABASE_PATTERN]);
      for (const row of rows) {
        if (row.url) urlSet.add(row.url);
      }
    } catch (err) {
      // Table might not exist in all environments
      console.warn(`  Warning: ${err.message.split('\n')[0]}`);
    }
  }

  // Run HTML queries and extract URLs with regex
  // Match both public and signed URLs for this project
  const { SUPABASE_URL_REGEX: supabaseUrlRegex } = await import('./lib/url-rewriter.js');

  for (const query of htmlQueries) {
    try {
      const { rows } = await pool.query(query, [SUPABASE_PATTERN]);
      for (const row of rows) {
        if (!row.html) continue;
        const matches = row.html.match(supabaseUrlRegex);
        if (matches) {
          for (const url of matches) urlSet.add(url);
        }
      }
    } catch (err) {
      console.warn(`  Warning: ${err.message.split('\n')[0]}`);
    }
  }

  // Also check occasions.features (JSONB array with background field)
  try {
    const { rows } = await pool.query(
      `SELECT features FROM occasions WHERE features IS NOT NULL AND features::TEXT LIKE $1`,
      [SUPABASE_PATTERN]
    );
    for (const row of rows) {
      const features = row.features;
      const text = JSON.stringify(features);
      const matches = text.match(supabaseUrlRegex);
      if (matches) {
        for (const url of matches) urlSet.add(url);
      }
    }
  } catch (err) {
    console.warn(`  Warning: ${err.message.split('\n')[0]}`);
  }

  return [...urlSet];
}

/**
 * Extract the R2 key from a Supabase URL.
 *
 * Handles:
 *   public-files/path/file.jpg  → path/file.jpg
 *   custom-files/path/file.jpg  → path/file.jpg
 *   sign/editor-files/file.jpg?token=...  → editor/file.jpg
 */
function urlToR2Key(url) {
  if (url.startsWith(SUPABASE_STORAGE_PREFIX)) {
    return url.substring(SUPABASE_STORAGE_PREFIX.length);
  }

  // Handle signed editor-files URLs (strip ?token=... query)
  const signedMatch = url.match(
    /\/storage\/v1\/object\/sign\/editor-files\/([^?]+)/
  );
  if (signedMatch) return 'editor/' + signedMatch[1];

  // Handle other public bucket patterns (e.g. custom-files)
  const publicMatch = url.match(/\/storage\/v1\/object\/public\/[^/]+\/(.+)$/);
  if (publicMatch) return publicMatch[1];

  return null;
}

/**
 * Download a file from a public URL.
 */
async function downloadFile(url) {
  const res = await fetch(url);
  if (!res.ok) {
    throw new Error(`HTTP ${res.status} downloading ${url}`);
  }
  return Buffer.from(await res.arrayBuffer());
}

/**
 * Upload a file to R2 via wrangler CLI.
 */
async function uploadToR2(r2Key, localPath, contentType) {
  const args = [
    'wrangler', 'r2', 'object', 'put',
    `festapp-images/${r2Key}`,
    '--file', localPath,
    '--content-type', contentType,
    '--remote',
  ];
  await execFileAsync('npx', args, { timeout: 30000 });
}

/**
 * Check if an object exists in R2 via wrangler CLI.
 */
async function r2ObjectExists(r2Key) {
  try {
    await execFileAsync('npx', [
      'wrangler', 'r2', 'object', 'get',
      `festapp-images/${r2Key}`,
      '--pipe',
      '--remote',
    ], { timeout: 15000, maxBuffer: 1024 }); // minimal buffer, we just check existence
    return true;
  } catch {
    return false;
  }
}

async function main() {
  const { dryRun, concurrency } = parseArgs();

  const databaseUrl = process.env.DATABASE_URL;
  if (!databaseUrl) {
    console.error('Missing required environment variable: DATABASE_URL');
    console.error('Set DATABASE_URL in .env or export it.');
    process.exit(1);
  }

  console.log(`\n=== Supabase Storage → R2 File Migration ===`);
  console.log(`Mode: ${dryRun ? 'DRY RUN (no uploads)' : 'LIVE MIGRATION'}`);
  console.log(`Concurrency: ${concurrency}`);
  console.log(`Target: R2 bucket "festapp-images"\n`);

  const pool = createPool(databaseUrl);

  try {
    console.log('Scanning database for Supabase Storage URLs...');
    const urls = await collectAllSupabaseUrls(pool);
    console.log(`Found ${urls.length} distinct Supabase URLs\n`);

    if (urls.length === 0) {
      console.log('No files to migrate.');
      return;
    }

    // Map URLs to R2 keys (only this project's Supabase instance)
    const filesToMigrate = [];
    let skippedOther = 0;
    for (const url of urls) {
      if (!url.includes(process.env.SUPABASE_PROJECT_REF)) {
        skippedOther++;
        continue;
      }
      const r2Key = urlToR2Key(url);
      if (!r2Key) {
        console.warn(`  SKIP (cannot parse key): ${url}`);
        continue;
      }
      filesToMigrate.push({ url, r2Key });
    }
    if (skippedOther > 0) {
      console.log(`Skipped ${skippedOther} URLs from other Supabase projects\n`);
    }

    if (dryRun) {
      console.log('Files to migrate:');
      for (const { url, r2Key } of filesToMigrate) {
        const mime = getMimeType(r2Key);
        console.log(`  ${r2Key}  [${mime}]`);
        console.log(`    ← ${url}`);
      }
      console.log(`\nTotal: ${filesToMigrate.length} files`);
      console.log('Run without --dry-run to migrate.');
      return;
    }

    // Create temp directory for downloads
    const tmpDir = join(tmpdir(), 'festapp-migration');
    await mkdir(tmpDir, { recursive: true });

    const limit = pLimit(concurrency);
    let success = 0;
    let failed = 0;
    let skipped = 0;

    const tasks = filesToMigrate.map(({ url, r2Key }) =>
      limit(async () => {
        const tmpFile = join(tmpDir, r2Key.replace(/\//g, '_'));
        try {
          // Check if already in R2
          const exists = await r2ObjectExists(r2Key);
          if (exists) {
            console.log(`  SKIP ${r2Key} (already exists in R2)`);
            skipped++;
            return;
          }

          // Download from Supabase
          const buffer = await downloadFile(url);

          // Write to temp file
          await writeFile(tmpFile, buffer);

          // Upload to R2 via wrangler
          const contentType = getMimeType(r2Key);
          await uploadToR2(r2Key, tmpFile, contentType);

          console.log(`  OK   ${r2Key} (${buffer.length} bytes, ${contentType})`);
          success++;
        } catch (err) {
          console.error(`  FAIL ${r2Key}: ${err.message}`);
          failed++;
        } finally {
          // Clean up temp file
          await unlink(tmpFile).catch(() => {});
        }
      })
    );

    await Promise.all(tasks);

    // Summary
    console.log(`\n=== Migration Summary ===`);
    console.log(`${success} migrated, ${failed} failed, ${skipped} skipped`);
    console.log(`Total in database: ${filesToMigrate.length}`);

    if (failed > 0) {
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
