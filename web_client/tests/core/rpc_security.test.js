
import { test } from 'node:test';
import assert from 'node:assert';
import { fileURLToPath } from 'url';
import { dirname } from 'path';

const SUPABASE_URL = process.env.SUPABASE_URL || 'https://api.festapp.net';
const ANON_KEY = process.env.SUPABASE_ANON_KEY;
const targetHost = new URL(SUPABASE_URL).hostname;
const targetIsCanonical = ['api.festapp.net', '127.0.0.1', 'localhost'].includes(targetHost);

if (!targetIsCanonical) {
    throw new Error(`Refusing non-canonical Supabase test target: ${targetHost}`);
}

const SECURED_FUNCTIONS = [
    // Sync Functions
    { name: 'add_sync_map', body: { p_source_name: 'test', p_target_org_id: 1, p_target_unit_id: 1, p_remote_link_base: 'https://test.com' } },
    { name: 'sync_source_via_dblink', body: { p_target_source_name: 'test' } },
    { name: 'setup_external_source_dblink', body: { p_source_name: 'test', p_host: 'localhost', p_user: 'test', p_password: 'test' } },
    
    // Cron & Seed Functions
    { name: 'apply_planned_changes', body: {} },
    { name: 'seed_org_with_admin', body: { p_org_name: 'test', p_unit_name: 'test', p_admin_email: 'test@test.com', p_admin_password: 'test' } },
    
    // Utility Generator Functions
    { name: 'generate_schema_ddl', body: { p_schema_name: 'public' } },
    { name: 'generate_schema_policies_ddl', body: { p_schema_name: 'public' } },
    { name: 'generate_schema_triggers_ddl', body: { p_schema_name: 'public' } },
    { name: 'generate_schema_rls_enable_ddl', body: { p_schema_name: 'public' } }
];

/*
 * TEST STRATEGY:
 * We attempt to call these restricted functions using the ANON (Public) key.
 * 
 * Expected Result:
 * Since we explicitly REVOKED execute permissions from PUBLIC/ANON, Supabase should reject 
 * the request with a 401 Unauthorized or 403 Forbidden, OR a specific error message 
 * about permission denied for the function.
 * 
 * If the REVOKE failed but the Internal Check works, it would return 200/500 with "Access Denied: Service role required".
 * Both are considered "PASS" for this security test (Defense in Depth).
 */

SECURED_FUNCTIONS.forEach((func) => {
    test(`Security: Public RPC call to '${func.name}' should be blocked`, {
        skip: ANON_KEY ? false : 'SUPABASE_ANON_KEY is required for the live self-hosted security test',
    }, async (t) => {
        const rpcUrl = `${SUPABASE_URL}/rest/v1/rpc/${func.name}`;
        console.log(`Testing Public Access to: ${rpcUrl}`);

        const response = await fetch(rpcUrl, {
            method: 'POST',
            headers: {
                'Content-Type': 'application/json',
                'apikey': ANON_KEY,
                'Authorization': `Bearer ${ANON_KEY}`
            },
            body: JSON.stringify(func.body)
        });

        const text = await response.text();
        console.log(`[${func.name}] Status: ${response.status}`);
        
        // 403 Forbidden / 401 Unauthorized = Blocked by REVOKE (Good)
        // 500 Internal Server Error = Blocked by something (Good if it's permission related)
        // 404 Not Found = Function might not exist or is hidden (Could be Good)
        
        let isSecured = false;
        
        if (!response.ok) {
            console.log(`[${func.name}] Request failed as expected with status ${response.status}. Body: ${text.substring(0, 100)}...`);
            isSecured = true;
        } else {
            // Function executed (Status 200 or similar). NOW verify if it was caught by internal logic
            console.log(`[${func.name}] Request returned OK (${response.status}). Checking for internal security error...`);
            const isInternalBlock = text.includes("Access Denied") || text.includes("Service role required");
            if (isInternalBlock) {
                 console.log(`[${func.name}] BLOCKED by Internal Logic Check. (Defense in Depth works)`);
                 isSecured = true;
            } else {
                 console.error(`[${func.name}] CRITICAL FAIL: Function executed successfully! Response: ${text}`);
            }
        }

        assert.ok(isSecured, `Function '${func.name}' must be blocked (Network Error or Internal Check), but allowed execution.`);
    });
});
