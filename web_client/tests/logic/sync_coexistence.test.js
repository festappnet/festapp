import { test } from 'node:test';
import assert from 'node:assert';
import fs from 'fs';
import path from 'path';
import { fileURLToPath } from 'url';
import pg from 'pg';

const { Client } = pg;
const __dirname = path.dirname(fileURLToPath(import.meta.url));

// Resolve path to .env.local (assuming run from web_client or root)
// We try looking up one level (if in web_client/tests -> web_client -> root)
const envPath = path.resolve(__dirname, '../../.env.local');

let client;

test('Sync Coexistence Integration Test', async (t) => {
    // 0. Setup DB Connection
    if (!fs.existsSync(envPath)) {
        console.warn("Skipping DB test: .env.local not found at " + envPath);
        return;
    }
    
    const envContent = fs.readFileSync(envPath, 'utf8');
    const envVars = {};
    envContent.split('\n').forEach(line => {
        const match = line.match(/^([^=]+)=(.*)$/);
        if (match) envVars[match[1].trim()] = match[2].trim().replace(/^['"]|['"]$/g, '');
    });
    
    // Fallback or specific variable
    const DB_URL = envVars['DATABASE_URL'];
    if (!DB_URL) {
        console.warn("Skipping DB test: DATABASE_URL not set in .env.local");
        return;
    }

    client = new Client({ connectionString: DB_URL, ssl: { rejectUnauthorized: false } });
    await client.connect();
    
    let nativeId;

    try {
        // 1. Find a synced occasion (prerequisite)
        const res = await client.query("SELECT * FROM public.occasions WHERE external_source = 'vstupenky_remote' LIMIT 1");
        
        let targetLink;
        if (res.rows.length === 0) {
            console.log("No synced occasions found. Creating a Mock Synced Occasion for test purposes...");
            // If no sync, we mock one to test the PRINCIPLE of duality
            targetLink = 'mock-sync-link-' + Date.now();
            await client.query(`
                INSERT INTO public.occasions (title, link, start_time, end_time, is_open, is_hidden, external_source, external_id)
                VALUES ('MOCK Synced', $1, NOW(), NOW(), true, false, 'vstupenky_remote', 999999)
            `, [targetLink]);
        } else {
            targetLink = res.rows[0].link;
            console.log(`Using existing synced link: '${targetLink}'`);
        }

        // 2. Insert Native Occasion with SAME link
        // This validates that the unique constraint on 'link' is gone.
        const testTitle = "TEST Native Duplicate " + Date.now();
        
        await t.test('Should allow inserting duplicate link (Native)', async () => {
             const insertRes = await client.query(`
                INSERT INTO public.occasions (title, link, start_time, end_time, is_open, is_hidden, external_source)
                VALUES ($1, $2, NOW(), NOW() + INTERVAL '1 hour', true, false, NULL)
                RETURNING id
            `, [testTitle, targetLink]);
            
            nativeId = insertRes.rows[0].id;
            assert.ok(nativeId, "Failed to return ID for native insert");
        });

        // 3. Verify Coexistence
        await t.test('Should have both occasions in DB', async () => {
            const checkRes = await client.query("SELECT id, title, external_source FROM public.occasions WHERE link = $1", [targetLink]);
            
            // Should be at least 2 (Synced + Native)
            // If we mocked one, it's 2. If we looked up existing, it's 2.
            // Note: If test runs multiple times without cleanup, might be > 2.
            assert.ok(checkRes.rows.length >= 2, `Expected >= 2 occasions with link '${targetLink}', found ${checkRes.rows.length}`);
            
            const hasSynced = checkRes.rows.some(r => r.external_source === 'vstupenky_remote');
            const hasNative = checkRes.rows.some(r => r.external_source === null); // native usually null or specific
            
            assert.ok(hasSynced, "Synced occasion missing");
            assert.ok(hasNative, "Native occasion missing");
        });

    } finally {
        // Cleanup Native
        if (nativeId) {
            await client.query("DELETE FROM public.occasions WHERE id = $1", [nativeId]);
        }
        // If we created a mock synced one, clean it?
        // Logic above mixed "find existing" vs "create new".
        // Better to minimal cleanup.
        await client.end();
    }
});
