const fs = require('fs');
const { createClient } = require('@supabase/supabase-js');
const { exec } = require('child_process');

const DEFAULT_SB_URL = "https://api.festapp.net";

function assertCanonicalTestTarget(value) {
    const url = new URL(value);
    const allowedHosts = new Set(['api.festapp.net', '127.0.0.1', 'localhost']);
    if (!allowedHosts.has(url.hostname)) {
        throw new Error(`Refusing non-canonical Supabase test target: ${url.hostname}`);
    }
    return url.origin;
}

// Args
const args = process.argv.slice(2);
let TEST_TOKEN = '00000000-0000-0000-0000-00000000TEST';
let USE_EXISTING = false;
let FROM_EMAIL = 'info@festapp.net'; // Must be verified sender in verify-email-identity

for (let i = 0; i < args.length; i++) {
    if (args[i] === '--token') TEST_TOKEN = args[i+1];
    if (args[i] === '--existing-token') {
        TEST_TOKEN = args[i+1];
        USE_EXISTING = true;
    }
    if (args[i] === '--from') FROM_EMAIL = args[i+1];
}

async function main() {
    const sbUrl = assertCanonicalTestTarget(process.env.SUPABASE_URL || DEFAULT_SB_URL);
    const sbKey = process.env.SUPABASE_SERVICE_ROLE_KEY;
    if (!sbKey) {
        throw new Error('SUPABASE_SERVICE_ROLE_KEY is required for this production integration test');
    }
    const supabase = createClient(sbUrl, sbKey, { db: { schema: 'eshop' } });
    let accountId = null;

    console.log("=== Real Email Integration Test ===");
    console.log("Target: bank.<token>@bank.festapp.net");

    // 1. Setup Account (same as simulation)
    if (!USE_EXISTING) {
        // Warning: This usually fails with Anon Key due to specific RLS. 
        // Best to use --existing-token for real test if you don't have Service Key.
        console.log("1. Setting up Test Bank Account...");
        const { data: account, error: accError } = await supabase
            .from('bank_accounts')
            .upsert({
                title: 'Real Email Test Account',
                account_number: 'REAL/0000',
                type: 'FIO',
                import_token: TEST_TOKEN,
                unit_id: 1 // Assumption: unit with id 1 exists
            }, { onConflict: 'account_number' })
            .select()
            .single();

        if (accError) {
            console.warn("⚠️  Create Account Failed:", accError.message);
            console.warn("   Using --existing-token is recommended for this test.");
        } else {
             console.log("   Account Created:", account.id);
             accountId = account.id;
        }
    } else {
        console.log("1. Using Existing Token:", TEST_TOKEN);
    }

    // 2. Send Real Email via AWS CLI
    console.log("2. Sending Real Email via AWS SES...");
    const toAddress = `bank.${TEST_TOKEN}@bank.festapp.net`;
    const subject = "Real Integration Test";
    const body = `Fio Banka
Castka: 123,45 CZK
Account: 111222333/0800
VS: 777777
Message: Real Email Test
ID: ${Date.now()}`;
    
    // Command
    const cmd = `aws ses send-email --from "${FROM_EMAIL}" --destination "ToAddresses=${toAddress}" --message "Subject={Data=${subject},Charset=utf8},Body={Text={Data='${body.replace(/\n/g, "\\n")}',Charset=utf8}}" --region eu-central-1`;
    
    console.log("   Executing AWS CLI...");
    
    await new Promise((resolve, reject) => {
        exec(cmd, (error, stdout, stderr) => {
            if (error) {
                 console.error("❌ Failed to send email:", stderr);
                 reject(error);
                 return;
            }
            console.log("   Email Sent! MessageId:", JSON.parse(stdout).MessageId);
            resolve();
        });
    });

    // 3. Verify
    console.log("3. Verifying Transaction in DB (Waiting 30s)...");
    
    // Verification loop (Longer wait for real email propagation: SES -> SNS -> Edge can take 5-10s)
    let found = false;
    for (let i = 0; i < 15; i++) { // 15 * 2s = 30s
        await new Promise(r => setTimeout(r, 2000));
        process.stdout.write(".");
        
        let query = supabase.from('transactions').select('*');
        if (accountId) {
             query = query.eq('bank_account_id', accountId);
        } else {
             query = query.order('created_at', { ascending: false }).limit(1);
        }

        const { data: txs } = await query;
        if (txs && txs.length > 0) {
            const created = new Date(txs[0].created_at);
            if ((new Date() - created) < 60000) { // Created in last minute
                 // Check content if possible
                 if (txs[0].amount === 123.45) { // Check amount match
                     console.log("\n✅ SUCCESS! Transaction found:", txs[0].id);
                     console.log("   Amount: 123.45 CZK");
                     found = true;
                     break;
                 }
            }
        }
    }
    console.log(""); 

    if (!found) {
        console.error("❌ Transaction not found in time.");
        console.log("Possible reasons:");
        console.log("- AWS SES Receipt Rule not active");
        console.log("- DNS propagation delay");
        console.log("- Edge Function failed (check Supabase logs)");
    } else {
        if (accountId) {
            console.log("4. Cleanup...");
            await supabase.from('bank_accounts').delete().eq('id', accountId);
        }
    }
}

main();
