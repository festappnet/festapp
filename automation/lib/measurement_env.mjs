import {readFileSync} from 'node:fs';
const line = readFileSync(process.argv[2], 'utf8').split(/\r?\n/).find(line => /^\s*(?:export\s+)?CLOUDFLARE_API_TOKEN\s*=/.test(line));
if (!line) { console.error('Env file missing CLOUDFLARE_API_TOKEN'); process.exit(1); }
let value = line.slice(line.indexOf('=') + 1).trim();
const quoted = value.match(/^("[^"\r\n]*"|'[^'\r\n]*')\s*(?:#.*)?$/);
if (quoted) value = quoted[1].slice(1, -1);
else value = value.replace(/\s*#.*$/, '').trim();
if (!value || /[\s"']/.test(value)) { console.error('Env file has empty or invalid CLOUDFLARE_API_TOKEN'); process.exit(1); }
process.stdout.write(value);
