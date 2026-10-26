import {spawnSync} from 'node:child_process';
import fs from 'node:fs';
const r = spawnSync('node', ['scripts/environment.mjs','run','cli','wp','eval-file','/var/www/html/wp-content/plugins/vstupenky-online-tests/seed.php'], {encoding:'utf8'});
if (r.status) { console.error('Seed failed', r.stderr); process.exit(1); }
const m = r.stdout.match(/VO_CREDENTIALS=(\{[^\n]+\})/);
if (!m) throw Error('Missing private seed receipt');
fs.writeFileSync('.private/wordpress-auth.json', m[1], {mode:0o600});
console.log('Seed: 5 pages, local administrator and subscriber. Credentials stored privately.');
