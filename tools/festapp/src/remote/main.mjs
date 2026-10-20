#!/usr/bin/env node
import { readFile, open, lstat } from 'node:fs/promises';
import { resolve, isAbsolute, dirname } from 'node:path';
import { generateKeyPairSync, randomBytes, randomUUID } from 'node:crypto';
import { parseRemoteConfig } from './config.mjs';
import { privateRoot } from '../context/profile.mjs';
import { safeError, check } from '../errors.mjs';
import { openRemoteStorage } from './storage.mjs';
import { createRemoteApp } from './server.mjs';

try {
    const args = process.argv.slice(2);
    if (args[0] === 'secrets' && args[1] === 'init' && args.length === 3) {
        check(isAbsolute(args[2]), 'INVALID_INPUT');
        await privateRoot(dirname(args[2]));
        const { privateKey } = generateKeyPairSync('rsa', { modulusLength: 2048 });
        const secrets = { schemaVersion: 1,
            storageKey: randomBytes(32).toString('base64url'),
            cookieKeys: [randomBytes(48).toString('base64url'), randomBytes(48).toString('base64url')],
            jwks: { keys: [{ ...privateKey.export({ format: 'jwk' }), kid: randomUUID(), use: 'sig', alg: 'RS256' }] } };
        const f = await open(args[2], 'wx', 0o600);
        try { await f.writeFile(JSON.stringify(secrets)); await f.sync(); } finally { await f.close(); }
        process.stdout.write('{"ok":true,"secretsCreated":true}\n');
    } else if (args[0] === 'check' && args.length === 2) {
        const c = parseRemoteConfig(JSON.parse(await readFile(args[1], 'utf8')));
        process.stdout.write(JSON.stringify({ ok: true, issuer: c.issuer, resource: c.resource,
            tenant: c.profile.tenantId, clients: c.clients.length, operators: c.operators.length }) + '\n');
    } else {
        check(args.length === 8 && args[0] === 'serve' && args[2] === '--secrets' &&
            args[4] === '--data' && args[6] === '--port', 'INVALID_COMMAND');
        const config = parseRemoteConfig(JSON.parse(await readFile(args[1], 'utf8')));
        const secretPath = resolve(args[3]), root = resolve(args[5]), port = Number(args[7]);
        check(Number.isInteger(port) && port > 1024 && port < 65536, 'INVALID_INPUT');
        check(!secretPath.startsWith(root + '/') && secretPath !== root, 'SEPARATE_SECRET_STORAGE_REQUIRED');
        const stat = await lstat(secretPath);
        check(stat.isFile() && !stat.isSymbolicLink() && !(stat.mode & 0o077) &&
            (!process.getuid || stat.uid === process.getuid()), 'INSECURE_SECRET_FILE');
        const secrets = JSON.parse(await readFile(secretPath, 'utf8'));
        check(secrets.schemaVersion === 1 && /^[A-Za-z0-9_-]{43}$/.test(secrets.storageKey), 'INVALID_STORAGE_KEY');
        const storage = await openRemoteStorage(root, Buffer.from(secrets.storageKey, 'base64url'));
        try {
            const { app } = createRemoteApp(config, storage, { ...secrets,
                audit: record => process.stderr.write(JSON.stringify(record) + '\n') });
            const listener = app.listen(port, '127.0.0.1', () => process.stderr.write('Festapp MCP listening on loopback\n'));
            let closing = false;
            const close = () => {
                if (closing) return;
                closing = true;
                const timer = setTimeout(() => listener.closeAllConnections(), 30000);
                timer.unref();
                listener.close(async () => { clearTimeout(timer); await storage.close(); });
            };
            process.once('SIGINT', close); process.once('SIGTERM', close);
            listener.on('error', async () => { await storage.close(); process.exitCode = 1; });
        } catch (e) { await storage.close(); throw e; }
    }
} catch (error) {
    process.stderr.write(JSON.stringify({ ok: false, error: safeError(error) }) + '\n');
    process.exitCode = 1;
}
