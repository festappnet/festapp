// Explicit acceptance gate, never discovered as an optional/skipped unit test.
// The caller must supply a marker-verified, fenced disposable database.
import assert from 'node:assert/strict';
import { readFile } from 'node:fs/promises';
import { openDisposableDatabase } from './postgres.mjs';

const db = await openDisposableDatabase(process.env.FESTAPP_MCP_TEST_DATABASE_URL);
try {
    assert.equal((await db.query('select bool_and(paused AND worker_url IS NULL) safe from email_capacity')).rows[0].safe, true);
    await db.query('BEGIN');
    await db.query('SET LOCAL ROLE postgres');
    await db.query(await readFile(new URL('../../../database/tests/helpers/assertions.sql', import.meta.url), 'utf8'));
    // Check the complete installed schema cut. Do not install selected functions
    // here: the fixture must have applied the real forward migration chain.
    await db.query(await readFile(new URL('../../../database/tests/canonical_mutation_source_parity_test.sql', import.meta.url), 'utf8'));
    console.log('Complete guarded disposable SQL source parity: PASS');
} finally {
    await db.query('ROLLBACK');
    await db.end();
}
