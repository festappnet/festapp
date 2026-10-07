#!/usr/bin/env node

/**
 * Rewrite all Supabase Storage URLs in the database to R2 URLs.
 *
 * Covers: images.link, icons.link, occasions.data (image, email_banner, map_layer),
 * occasions.features (ticket background), units.data, organizations.data (email_banner),
 * and all HTML columns (information, events, news, places, user_group_info,
 * email_wrappers, email_templates, forms).
 *
 * Usage:
 *   node rewrite-urls.js --dry-run     # Preview changes without modifying database
 *   node rewrite-urls.js               # Apply URL rewrites
 *
 * Requires: DATABASE_URL environment variable
 */

import { config } from 'dotenv';
import { createPool, closePool } from './lib/db.js';
import { rewriteUrl, containsSupabaseUrl, SUPABASE_PATTERN } from './lib/url-rewriter.js';
import { rewriteHtml } from './lib/html-rewriter.js';

config();

// Parse CLI flags
const dryRun = process.argv.includes('--dry-run');

function truncate(str, len = 80) {
  if (!str) return '(null)';
  const s = String(str);
  return s.length > len ? s.substring(0, len) + '...' : s;
}

// Track summary stats
const stats = {};
function recordStat(table, column, count) {
  const key = `${table}.${column}`;
  stats[key] = (stats[key] || 0) + count;
}

// ─── Rewrite: images.link ────────────────────────────────────────

async function rewriteImagesLink(pool) {
  const { rows } = await pool.query(
    `SELECT id, link FROM images WHERE link LIKE $1`,
    [SUPABASE_PATTERN]
  );
  console.log(`[images.link] Found ${rows.length} rows with Supabase URLs`);
  recordStat('images', 'link', rows.length);

  for (const row of rows) {
    const { newUrl, changed } = rewriteUrl(row.link);
    if (!changed) continue;

    if (dryRun) {
      console.log(`  id=${row.id}: ${truncate(row.link)} → ${truncate(newUrl)}`);
    } else {
      try {
        await pool.query(`UPDATE images SET link = $1 WHERE id = $2`, [newUrl, row.id]);
      } catch (err) {
        console.error(`  ERROR updating images id=${row.id}: ${err.message}`);
      }
    }
  }
}

// ─── Rewrite: icons.link ─────────────────────────────────────────

async function rewriteIconsLink(pool) {
  const { rows } = await pool.query(
    `SELECT id, link FROM icons WHERE link LIKE $1`,
    [SUPABASE_PATTERN]
  );
  console.log(`[icons.link] Found ${rows.length} rows with Supabase URLs`);
  recordStat('icons', 'link', rows.length);

  for (const row of rows) {
    const { newUrl, changed } = rewriteUrl(row.link);
    if (!changed) continue;

    if (dryRun) {
      console.log(`  id=${row.id}: ${truncate(row.link)} → ${truncate(newUrl)}`);
    } else {
      try {
        await pool.query(`UPDATE icons SET link = $1 WHERE id = $2`, [newUrl, row.id]);
      } catch (err) {
        console.error(`  ERROR updating icons id=${row.id}: ${err.message}`);
      }
    }
  }
}

// ─── Rewrite: occasions.data (image, email_banner) ──────────────

async function rewriteOccasionsData(pool) {
  const { rows } = await pool.query(
    `SELECT id, data FROM occasions
     WHERE data->>'image' LIKE $1
        OR data->>'email_banner' LIKE $1`,
    [SUPABASE_PATTERN]
  );
  console.log(`[occasions.data] Found ${rows.length} rows with Supabase URLs in image/email_banner`);
  recordStat('occasions', 'data.image/email_banner', rows.length);

  for (const row of rows) {
    const imageUrl = row.data?.image;
    const bannerUrl = row.data?.email_banner;

    if (imageUrl && containsSupabaseUrl(imageUrl)) {
      const { newUrl } = rewriteUrl(imageUrl);
      if (dryRun) {
        console.log(`  id=${row.id} image: ${truncate(imageUrl)} → ${truncate(newUrl)}`);
      } else {
        try {
          await pool.query(
            `UPDATE occasions SET data = jsonb_set(data, '{image}', to_jsonb($1::text)) WHERE id = $2`,
            [newUrl, row.id]
          );
        } catch (err) {
          console.error(`  ERROR updating occasions.data.image id=${row.id}: ${err.message}`);
        }
      }
    }

    if (bannerUrl && containsSupabaseUrl(bannerUrl)) {
      const { newUrl } = rewriteUrl(bannerUrl);
      if (dryRun) {
        console.log(`  id=${row.id} email_banner: ${truncate(bannerUrl)} → ${truncate(newUrl)}`);
      } else {
        try {
          await pool.query(
            `UPDATE occasions SET data = jsonb_set(data, '{email_banner}', to_jsonb($1::text)) WHERE id = $2`,
            [newUrl, row.id]
          );
        } catch (err) {
          console.error(`  ERROR updating occasions.data.email_banner id=${row.id}: ${err.message}`);
        }
      }
    }
  }
}

// ─── Rewrite: occasions.data.logo ────────────────────────────────

async function rewriteOccasionsLogo(pool) {
  const { rows } = await pool.query(
    `SELECT id, data FROM occasions WHERE data->>'logo' LIKE $1`,
    [SUPABASE_PATTERN]
  );
  console.log(`[occasions.data.logo] Found ${rows.length} rows with Supabase URLs`);
  recordStat('occasions', 'data.logo', rows.length);

  for (const row of rows) {
    const logoUrl = row.data?.logo;
    if (!containsSupabaseUrl(logoUrl)) continue;

    const { newUrl } = rewriteUrl(logoUrl);
    if (dryRun) {
      console.log(`  id=${row.id}: ${truncate(logoUrl)} → ${truncate(newUrl)}`);
    } else {
      try {
        await pool.query(
          `UPDATE occasions SET data = jsonb_set(data, '{logo}', to_jsonb($1::text)) WHERE id = $2`,
          [newUrl, row.id]
        );
      } catch (err) {
        console.error(`  ERROR updating occasions.data.logo id=${row.id}: ${err.message}`);
      }
    }
  }
}

// ─── Rewrite: occasions.data map_layer fields ────────────────────

async function rewriteOccasionsMapLayer(pool) {
  const { rows } = await pool.query(
    `SELECT id, data FROM occasions
     WHERE data->'map_layer'->>'layer_link' LIKE $1
        OR data->'map_layer'->>'logo' LIKE $1`,
    [SUPABASE_PATTERN]
  );
  console.log(`[occasions.data.map_layer] Found ${rows.length} rows with Supabase URLs`);
  recordStat('occasions', 'data.map_layer', rows.length);

  for (const row of rows) {
    const layerLink = row.data?.map_layer?.layer_link;
    const logo = row.data?.map_layer?.logo;

    if (layerLink && containsSupabaseUrl(layerLink)) {
      const { newUrl } = rewriteUrl(layerLink);
      if (dryRun) {
        console.log(`  id=${row.id} map_layer.layer_link: ${truncate(layerLink)} → ${truncate(newUrl)}`);
      } else {
        try {
          await pool.query(
            `UPDATE occasions SET data = jsonb_set(data, '{map_layer,layer_link}', to_jsonb($1::text)) WHERE id = $2`,
            [newUrl, row.id]
          );
        } catch (err) {
          console.error(`  ERROR updating occasions.data.map_layer.layer_link id=${row.id}: ${err.message}`);
        }
      }
    }

    if (logo && containsSupabaseUrl(logo)) {
      const { newUrl } = rewriteUrl(logo);
      if (dryRun) {
        console.log(`  id=${row.id} map_layer.logo: ${truncate(logo)} → ${truncate(newUrl)}`);
      } else {
        try {
          await pool.query(
            `UPDATE occasions SET data = jsonb_set(data, '{map_layer,logo}', to_jsonb($1::text)) WHERE id = $2`,
            [newUrl, row.id]
          );
        } catch (err) {
          console.error(`  ERROR updating occasions.data.map_layer.logo id=${row.id}: ${err.message}`);
        }
      }
    }
  }
}

// ─── Rewrite: occasions.features (ticket background) ─────────────

async function rewriteOccasionsFeatures(pool) {
  const { rows } = await pool.query(
    `SELECT id, features FROM occasions
     WHERE features IS NOT NULL AND features::TEXT LIKE $1`,
    [SUPABASE_PATTERN]
  );
  console.log(`[occasions.features] Found ${rows.length} rows with Supabase URLs`);
  recordStat('occasions', 'features', rows.length);

  for (const row of rows) {
    let features = row.features;
    let changed = false;

    if (Array.isArray(features)) {
      features = features.map((item) => {
        if (item && typeof item === 'object' && containsSupabaseUrl(item.background)) {
          const { newUrl } = rewriteUrl(item.background);
          changed = true;
          return { ...item, background: newUrl };
        }
        return item;
      });
    } else if (typeof features === 'object' && features !== null) {
      // Handle object with background field
      if (containsSupabaseUrl(features.background)) {
        const { newUrl } = rewriteUrl(features.background);
        features = { ...features, background: newUrl };
        changed = true;
      }
    }

    if (!changed) continue;

    if (dryRun) {
      console.log(`  id=${row.id}: features updated (ticket background URLs rewritten)`);
    } else {
      try {
        await pool.query(
          `UPDATE occasions SET features = $1::jsonb WHERE id = $2`,
          [JSON.stringify(features), row.id]
        );
      } catch (err) {
        console.error(`  ERROR updating occasions.features id=${row.id}: ${err.message}`);
      }
    }
  }
}

// ─── Rewrite: JSONB email_banner (units, organizations) ──────────

async function rewriteJsonbEmailBanner(pool, table) {
  const { rows } = await pool.query(
    `SELECT id, data FROM ${table} WHERE data->>'email_banner' LIKE $1`,
    [SUPABASE_PATTERN]
  );
  console.log(`[${table}.data.email_banner] Found ${rows.length} rows with Supabase URLs`);
  recordStat(table, 'data.email_banner', rows.length);

  for (const row of rows) {
    const bannerUrl = row.data?.email_banner;
    if (!containsSupabaseUrl(bannerUrl)) continue;

    const { newUrl } = rewriteUrl(bannerUrl);
    if (dryRun) {
      console.log(`  id=${row.id}: ${truncate(bannerUrl)} → ${truncate(newUrl)}`);
    } else {
      try {
        await pool.query(
          `UPDATE ${table} SET data = jsonb_set(data, '{email_banner}', to_jsonb($1::text)) WHERE id = $2`,
          [newUrl, row.id]
        );
      } catch (err) {
        console.error(`  ERROR updating ${table}.data.email_banner id=${row.id}: ${err.message}`);
      }
    }
  }
}

// ─── Rewrite: HTML columns ───────────────────────────────────────

async function rewriteHtmlColumn(pool, table, column) {
  const { rows } = await pool.query(
    `SELECT id, "${column}" FROM "${table}" WHERE "${column}" LIKE $1`,
    [SUPABASE_PATTERN]
  );
  console.log(`[${table}.${column}] Found ${rows.length} rows with Supabase URLs`);
  recordStat(table, column, rows.length);

  for (const row of rows) {
    const htmlContent = row[column];
    if (!htmlContent) continue;

    const result = rewriteHtml(htmlContent);
    if (!result.changed) continue;

    if (dryRun) {
      console.log(`  id=${row.id}: ${result.count} URL(s) rewritten in HTML`);
    } else {
      try {
        await pool.query(
          `UPDATE "${table}" SET "${column}" = $1 WHERE id = $2`,
          [result.html, row.id]
        );
      } catch (err) {
        console.error(`  ERROR updating ${table}.${column} id=${row.id}: ${err.message}`);
      }
    }
  }
}

// ─── Main ────────────────────────────────────────────────────────

async function main() {
  const databaseUrl = process.env.DATABASE_URL;
  if (!databaseUrl) {
    console.error('Missing required environment variable: DATABASE_URL');
    console.error('Set DATABASE_URL to your PostgreSQL connection string.');
    process.exit(1);
  }

  console.log(`\n=== Database URL Rewrite ===`);
  console.log(`Mode: ${dryRun ? 'DRY RUN (no writes)' : 'LIVE REWRITE'}`);
  console.log(`Database: ${databaseUrl.replace(/:[^:@]+@/, ':***@')}\n`);

  const pool = createPool(databaseUrl);

  try {
    // Plain text link columns
    console.log('--- Plain text columns ---');
    await rewriteImagesLink(pool);
    await rewriteIconsLink(pool);

    // JSONB data fields
    console.log('\n--- JSONB data fields ---');
    await rewriteOccasionsData(pool);
    await rewriteOccasionsLogo(pool);
    await rewriteOccasionsMapLayer(pool);
    await rewriteOccasionsFeatures(pool);
    await rewriteJsonbEmailBanner(pool, 'units');
    await rewriteJsonbEmailBanner(pool, 'organizations');

    // HTML columns
    console.log('\n--- HTML columns ---');
    await rewriteHtmlColumn(pool, 'information', 'description');
    await rewriteHtmlColumn(pool, 'events', 'description');
    await rewriteHtmlColumn(pool, 'news', 'message');
    await rewriteHtmlColumn(pool, 'places', 'description');
    await rewriteHtmlColumn(pool, 'user_group_info', 'description');
    await rewriteHtmlColumn(pool, 'email_wrappers', 'html');
    await rewriteHtmlColumn(pool, 'email_templates', 'html');
    await rewriteHtmlColumn(pool, 'forms', 'header');
    await rewriteHtmlColumn(pool, 'forms', 'header_off');

    // Summary
    console.log('\n=== Rewrite Summary ===');
    console.log(`Mode: ${dryRun ? 'DRY RUN' : 'APPLIED'}`);
    console.log('');
    let totalRows = 0;
    for (const [key, count] of Object.entries(stats)) {
      if (count > 0) {
        console.log(`  ${key}: ${count} rows`);
        totalRows += count;
      }
    }
    if (totalRows === 0) {
      console.log('  No Supabase URLs found in any column.');
    } else {
      console.log(`\n  Total: ${totalRows} rows across all columns`);
    }
  } finally {
    await closePool(pool);
  }
}

main().catch((err) => {
  console.error('Fatal error:', err.message);
  process.exit(1);
});
