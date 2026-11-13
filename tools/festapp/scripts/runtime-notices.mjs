// Generate notices from the exact installed production dependency graph.
// Usage: pnpm licenses list --prod --json | node scripts/runtime-notices.mjs <prefix>
import { readFile, readdir, writeFile } from 'node:fs/promises';
import { join } from 'node:path';
import { createHash } from 'node:crypto';
const chunks = [];
for await (const chunk of process.stdin) chunks.push(chunk);
const inventory = JSON.parse(Buffer.concat(chunks).toString());
const packages = [], notices = [];
const installed = Object.values(inventory).flat();
for (const [license, entries] of Object.entries(inventory)) {
    if (!['MIT', 'Apache-2.0', 'ISC', 'BSD-3-Clause', '0BSD'].includes(license))
        throw new Error(`Review required for runtime license: ${license}`);
    for (const entry of entries) {
        const documents = [];
        // Native artifacts from these workspaces carry the parent package's
        // declared license; retain its exact-version notice in the distribution.
        const parentName = ['@napi-rs/canvas', '@napi-rs/keyring'].find(name => entry.name.startsWith(name + '-'));
        const parent = parentName && installed.find(p => p.name === parentName && p.license === license &&
            JSON.stringify(p.versions) === JSON.stringify(entry.versions));
        for (const directory of [...entry.paths, ...(parent?.paths ?? [])]) {
            for (const name of (await readdir(directory)).sort()) {
                if (!/^(licen[cs]e|notice|copying)(\..*)?$/i.test(name)) continue;
                const text = await readFile(join(directory, name), 'utf8');
                const sha256 = createHash('sha256').update(text).digest('hex');
                if (documents.some(d => d.sha256 === sha256)) continue;
                documents.push({ name, sha256 });
                notices.push(`\n===== ${entry.name} ${entry.versions.join(', ')} - ${name} =====\n${text}\n`);
            }
        }
        if (!documents.length && entry.name === 'koa-compose' && JSON.stringify(entry.versions) === '["4.1.0"]') {
            const text = await readFile(new URL('../licenses/koa-compose-4.1.0/LICENSE', import.meta.url), 'utf8');
            documents.push({ name: 'LICENSE (upstream notice retained in distribution)', sha256: createHash('sha256').update(text).digest('hex') });
            notices.push(`\n===== koa-compose 4.1.0 - upstream LICENSE =====\n${text}\n`);
        }
        if (!documents.length) throw new Error(`Missing runtime notices: ${entry.name}`);
        packages.push({ name: entry.name, versions: entry.versions, license, documents });
    }
}
packages.sort((a, b) => a.name.localeCompare(b.name));
await writeFile(process.argv[2] + '.json', JSON.stringify({ schemaVersion: 1, packages }, null, 2) + '\n');
await writeFile(process.argv[2] + '.txt', 'Third-party production dependencies. Original license and copyright notices follow. Native embedded-library notices and source availability are also distributed in tools/festapp/licenses/.\n' + notices.join(''));
