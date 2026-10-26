import fs from 'node:fs';
const base = new URL('../.private/', import.meta.url);
const status = JSON.parse(fs.readFileSync(new URL('backend-status.json', base), 'utf8'));
if (status.API_URL !== 'http://127.0.0.1:59821') throw Error('Disposable backend required');
fs.writeFileSync(new URL('flutter-defines.json', base), JSON.stringify({FESTAPP_SUPABASE_URL:status.API_URL,FESTAPP_SUPABASE_ANON_KEY:status.ANON_KEY}), {mode:0o600});
console.log('Prepared private loopback-only Flutter defines');
