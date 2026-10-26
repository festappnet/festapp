#!/usr/bin/env node

/**
 * Orphan image detection — lists R2 keys not referenced in any database column.
 *
 * Compares all objects in the R2 bucket against URLs referenced in the database
 * (same 18+ columns as verify.js). Outputs orphan objects with key and size.
 *
 * Usage:
 *   node find-orphans.js              # Human-readable summary to stderr
 *   node find-orphans.js --json       # JSON array to stdout
 *   node find-orphans.js --output orphans.json  # Write JSON to file
 *
 * Requires: DATABASE_URL, CF_ACCOUNT_ID, R2_ACCESS_KEY_ID,
 *           R2_SECRET_ACCESS_KEY, R2_BUCKET_NAME
 *
 * Exit code: 0 always (orphans are informational, not errors)
 */

import fs from 'node:fs';
import { config } from 'dotenv';
import { createPool, closePool } from './lib/db.js';
import { createR2Client } from './lib/r2-client.js';
import { ListObjectsV2Command } from '@aws-sdk/client-s3';

config();

// Orphan detection reads only the canonical public delivery host. Importing the
// migration URL rewriter here would incorrectly require a source project ref.
const R2_HOST = 'img.festapp.net';
const R2_LIKE_PATTERN = `%${R2_HOST}%`;

// ─── CLI Flags ──────────────────────────────────────────────────

function parseArgs() {
  const args = process.argv.slice(2);
  const jsonOutput = args.includes('--json');
  let outputFile = null;
  const outIdx = args.indexOf('--output');
  if (outIdx !== -1 && args[outIdx + 1]) {
    outputFile = args[outIdx + 1];
  }
  return { jsonOutput, outputFile };
}

// ─── Environment Validation ─────────────────────────────────────

function validateEnv() {
  const required = [
    'DATABASE_URL',
    'CF_ACCOUNT_ID',
    'R2_ACCESS_KEY_ID',
    'R2_SECRET_ACCESS_KEY',
    'R2_BUCKET_NAME',
  ];
  const missing = required.filter((key) => !process.env[key]);
  if (missing.length > 0) {
    console.error('Missing required environment variables:');
    missing.forEach((key) => console.error(`  - ${key}`));
    console.error('\nCopy .env.example to .env and fill in the values.');
    process.exit(1);
  }
}

// ─── R2 Listing (with sizes) ────────────────────────────────────

async function listR2Objects(r2, bucket) {
  const objects = [];
  let continuationToken = undefined;

  while (true) {
    const response = await r2.send(
      new ListObjectsV2Command({
        Bucket: bucket,
        ContinuationToken: continuationToken,
      })
    );

    if (response.Contents) {
      for (const obj of response.Contents) {
        objects.push({ key: obj.Key, size: obj.Size || 0 });
      }
    }

    if (!response.IsTruncated) break;
    continuationToken = response.NextContinuationToken;
  }

  return objects;
}

// ─── URL Extraction from Database ───────────────────────────────

function extractR2UrlsFromText(text) {
  const urls = [];
  if (!text) return urls;
  const escapedHost = R2_HOST.replace(/\./g, '\\.');
  const regex = new RegExp(`https://${escapedHost}/[^\\s"'<>)]+`, 'g');
  let match;
  while ((match = regex.exec(text)) !== null) {
    urls.push(match[0]);
  }
  return urls;
}

async function extractReferencedUrls(pool) {
  const allUrls = [];

  // JSONB / plain text columns — extract URLs directly
  const directQuery = `
    SELECT link AS url FROM images WHERE link LIKE $1
    UNION ALL
    SELECT link FROM icons WHERE link LIKE $1
    UNION ALL
    SELECT data->>'image' FROM occasions WHERE data->>'image' LIKE $1
    UNION ALL
    SELECT data->>'email_banner' FROM occasions WHERE data->>'email_banner' LIKE $1
    UNION ALL
    SELECT data->'map_layer'->>'layer_link' FROM occasions WHERE data->'map_layer'->>'layer_link' LIKE $1
    UNION ALL
    SELECT data->'map_layer'->>'logo' FROM occasions WHERE data->'map_layer'->>'logo' LIKE $1
    UNION ALL
    SELECT data->>'logo' FROM occasions WHERE data->>'logo' LIKE $1
    UNION ALL
    SELECT data->>'email_banner' FROM units WHERE data->>'email_banner' LIKE $1
    UNION ALL
    SELECT data->>'email_banner' FROM organizations WHERE data->>'email_banner' LIKE $1
  `;

  const { rows: directRows } = await pool.query(directQuery, [R2_LIKE_PATTERN]);
  for (const row of directRows) {
    if (row.url) allUrls.push(row.url);
  }

  // occasions.features — extract R2 URLs from stringified JSONB
  const { rows: featureRows } = await pool.query(
    `SELECT features::TEXT AS txt FROM occasions WHERE features IS NOT NULL AND features::TEXT LIKE $1`,
    [R2_LIKE_PATTERN]
  );
  for (const row of featureRows) {
    allUrls.push(...extractR2UrlsFromText(row.txt));
  }

  // HTML columns — extract R2 URLs via regex
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

  for (const [table, column] of htmlColumns) {
    const { rows: htmlRows } = await pool.query(
      `SELECT "${column}" AS content FROM "${table}" WHERE "${column}" LIKE $1`,
      [R2_LIKE_PATTERN]
    );
    for (const row of htmlRows) {
      allUrls.push(...extractR2UrlsFromText(row.content));
    }
  }

  return allUrls;
}

// ─── URL to R2 Key ──────────────────────────────────────────────

function urlToR2Key(url) {
  if (!url) return '';

  // Handle /cdn-cgi/image/w=300,f=auto/{key} resize URLs
  if (url.includes('/cdn-cgi/image/')) {
    const parts = url.split('/cdn-cgi/image/');
    if (parts[1]) {
      const afterParams = parts[1];
      const slashIdx = afterParams.indexOf('/');
      return slashIdx !== -1 ? afterParams.substring(slashIdx + 1) : afterParams;
    }
  }

  // Direct R2 URL — strip prefix
  return url.replace(R2_PREFIX, '');
}

// ─── Main ───────────────────────────────────────────────────────

async function main() {
  const { jsonOutput, outputFile } = parseArgs();
  validateEnv();

  const r2Bucket = process.env.R2_BUCKET_NAME;

  console.error(`\n=== Orphan Image Detection ===`);
  console.error(`R2 bucket: ${r2Bucket}`);
  console.error(`Database: ${process.env.DATABASE_URL.replace(/:[^:@]+@/, ':***@')}\n`);

  // Step 1: List all R2 objects with sizes
  console.error('Listing R2 objects...');
  const r2 = createR2Client(process.env);
  const r2Objects = await listR2Objects(r2, r2Bucket);
  console.error(`Found ${r2Objects.length} objects in R2\n`);

  // Step 2: Extract all referenced R2 URLs from database
  console.error('Scanning database for referenced R2 URLs...');
  const pool = createPool(process.env.DATABASE_URL);

  let referencedKeys;
  try {
    const allUrls = await extractReferencedUrls(pool);
    referencedKeys = new Set(allUrls.map(urlToR2Key).filter(Boolean));
    console.error(`Found ${referencedKeys.size} unique referenced keys\n`);
  } finally {
    await closePool(pool);
  }

  // Step 3: Compute orphans
  const orphans = r2Objects.filter((obj) => !referencedKeys.has(obj.key));

  // Step 4: Output
  const totalSize = orphans.reduce((sum, o) => sum + o.size, 0);
  const sizeMB = (totalSize / (1024 * 1024)).toFixed(2);

  console.error(`=== Orphan Detection Summary ===`);
  console.error(`R2 objects: ${r2Objects.length}`);
  console.error(`Referenced in DB: ${referencedKeys.size}`);
  console.error(`Orphans: ${orphans.length}`);
  console.error(`Total orphan size: ${sizeMB} MB\n`);

  if (jsonOutput || outputFile) {
    const output = JSON.stringify(orphans, null, 2);
    if (outputFile) {
      fs.writeFileSync(outputFile, output);
      console.error(`Orphan list written to ${outputFile}`);
    } else {
      console.log(output);
    }
  } else {
    // Human-readable list
    if (orphans.length === 0) {
      console.log('No orphan images found.');
    } else {
      console.log(`Orphan images (${orphans.length}):\n`);
      for (const orphan of orphans) {
        const sizeKB = (orphan.size / 1024).toFixed(1);
        console.log(`  ${orphan.key}  (${sizeKB} KB)`);
      }
      console.log(`\nTotal: ${orphans.length} orphans, ${sizeMB} MB`);
    }
  }
}

main().catch((err) => {
  console.error('Fatal error:', err.message);
  process.exit(1);
});
