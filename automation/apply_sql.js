const { Client } = require('pg');
const fs = require('fs');
const path = require('path');

// Load .env.local
const envPath = path.resolve(__dirname, '../.env.local');
const envVars = {};
if (fs.existsSync(envPath)) {
    fs.readFileSync(envPath, 'utf8').split('\n').forEach(line => {
        const [k, v] = line.split('=');
        if (k && v) envVars[k.trim()] = v.trim();
    });
}
const DB_URL = process.env.DATABASE_URL || envVars['DATABASE_URL'];

if (!DB_URL) {
    console.error("No DATABASE_URL found.");
    process.exit(1);
}

const file = process.argv[2];
if (!file) {
    console.error("Usage: node apply_sql.js <path_to_sql_file>");
    process.exit(1);
}

const sql = fs.readFileSync(file, 'utf8');

const client = new Client({ connectionString: DB_URL, ssl: { rejectUnauthorized: false } });

(async () => {
    try {
        await client.connect();
        console.log(`Executing ${file}...`);
        await client.query(sql);
        console.log("Success.");
    } catch (e) {
        console.error("Error:", e.message);
        process.exit(1);
    } finally {
        await client.end();
    }
})();
