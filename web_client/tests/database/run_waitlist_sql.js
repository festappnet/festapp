// Focused SQL runner: no sequence reset and every file owns an isolated transaction.
import pg from 'pg';
import fs from 'node:fs/promises';
import path from 'node:path';
const url = process.env.DATABASE_URL;
if (!url) throw new Error('DATABASE_URL is required');
const parsed = new URL(url);
if (!['127.0.0.1', 'localhost'].includes(parsed.hostname) || parsed.port !== '56922') {
  throw new Error('Waitlist regression runner requires the dedicated disposable DB on localhost:56922');
}
const helper = await fs.readFile('database/tests/helpers/assertions.sql', 'utf8');
let failed = 0;
for (const file of process.argv.slice(2)) {
  const client = new pg.Client({ connectionString: url });
  try {
    await client.connect();
    await client.query('BEGIN');
    await client.query(helper);
    await client.query(await fs.readFile(file, 'utf8'));
    console.log(`PASS ${path.basename(file)}`);
  } catch (error) {
    failed++;
    console.error(`FAIL ${file}: ${error.message}${error.context ? `\n${error.context}` : ''}`);
  } finally {
    await client.query('ROLLBACK').catch(() => {});
    await client.end();
  }
}
process.exitCode = failed ? 1 : 0;
