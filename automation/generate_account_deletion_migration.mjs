import fs from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';

const root = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '..');
const table = fs.readFileSync(path.join(root, 'database/tables/account_deletion_requests.sql'), 'utf8');
const functions = fs.readFileSync(path.join(root, 'database/functions/account_deletion/account_deletion_contract.sql'), 'utf8');
const templates = fs.readFileSync(path.join(root, 'database/seeds/account_deletion_email_templates.sql'), 'utf8');
const header = `-- Generated from canonical account-deletion SQL sources.\n-- Do not apply without the production migration gate.\nSET lock_timeout = '5s';\nSET statement_timeout = '120s';\nSET check_function_bodies = off;\n\nALTER TABLE eshop.bank_account_requests ALTER COLUMN created_by DROP NOT NULL;\n\n`;
const output = path.join(root, 'supabase/migrations/20260803120000_csm_account_deletion.sql');
fs.writeFileSync(output, header + table + '\n' + functions + '\n' + templates + '\nSET check_function_bodies = on;\n');
console.log(path.relative(root, output));
