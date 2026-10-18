import fs from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';

const root = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '..');
const read = name => fs.readFileSync(path.join(root, name), 'utf8');
const contract = read('database/functions/account_deletion/account_deletion_contract.sql');
const update = contract.match(/CREATE OR REPLACE FUNCTION public\.update_account_deletion_job\([\s\S]+?\n\$\$;/)?.[0];
if (!update) throw new Error('canonical account job owner not found');
const sql = [
  '-- Generated from canonical asset table/cleanup and account job sources.',
  '-- Staged only: activate after verified inventory import, copy and delta gates.',
  "SET lock_timeout='5s';", "SET statement_timeout='120s';",
  read('database/tables/canonical_assets.sql'),
  read('database/functions/account_deletion/asset_cleanup.sql'),
  update,
  'DROP FUNCTION public.get_account_deletion_storage_batch(uuid,integer);',
  "NOTIFY pgrst, 'reload schema';", '',
].join('\n');
const target = path.join(root, 'supabase/migrations/20261018010000_storage_asset_cleanup.sql');
if (process.argv.includes('--check')) {
  if (read('supabase/migrations/20261018010000_storage_asset_cleanup.sql') !== sql) throw new Error('asset migration source parity');
} else fs.writeFileSync(target, sql);
