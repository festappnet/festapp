import {readFileSync} from 'node:fs';
try {
  let value;
  if (process.argv[2] === '--wrangler-json') {
    const data = JSON.parse(readFileSync(0, 'utf8'));
    if (data.type !== 'oauth') throw Error();
    value = data.token;
  } else {
    const line = readFileSync(process.argv[2], 'utf8').split(/\r?\n/).find(line => /^\s*(?:export\s+)?CLOUDFLARE_API_TOKEN\s*=/.test(line));
    if (!line) throw Error();
    value = line.slice(line.indexOf('=') + 1).trim();
    const quoted = value.match(/^("[^"\r\n]*"|'[^'\r\n]*')\s*(?:#.*)?$/);
    if (quoted) value = quoted[1].slice(1, -1);
    else value = value.replace(/\s*#.*$/, '').trim();
  }
  if (typeof value !== 'string' || !value || /[\s"'\\]/.test(value)) throw Error();
  process.stdout.write(value);
} catch {
  console.error('Env file or Wrangler OAuth credential is missing or invalid');
  process.exitCode = 1;
}
