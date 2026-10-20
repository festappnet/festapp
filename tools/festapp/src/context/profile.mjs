import { createHash } from 'node:crypto';
import { readFile, mkdir, open, lstat } from 'node:fs/promises';
import { join, isAbsolute } from 'node:path';
import { homedir } from 'node:os';
import { z } from 'zod';
import { check } from '../errors.mjs';
import { canonicalBackendProfileSha256 } from '../../../../automation/lib/backend_activation_manifest.mjs';
export const configHome = () =>
    process.env.FESTAPP_OPERATOR_HOME ||
    join(homedir(), 'Library', 'Application Support', 'Festapp Operator');
const nameSchema = z.string().regex(/^[a-zA-Z0-9][a-zA-Z0-9_-]{0,63}$/);
const schema = z.strictObject({
    schemaVersion: z.literal(1),
    name: nameSchema,
    kind: z.enum(['canonical', 'disposable-local']),
    tenantId: z.string().min(1).max(100),
    backendOrigin: z.url(),
    publicApiKey: z.string().min(1).max(4096),
    organizationId: z.number().int().positive(),
    activationUrl: z.url(),
    activationSha256: z.string().regex(/^[a-f0-9]{64}$/),
    canonicalProfileSha256: z.string().regex(/^[a-f0-9]{64}$/),
    generation: z.literal(1),
});
export const digest = (value) =>
    createHash('sha256').update(value).digest('hex');
export function parseProfile(raw) {
    const p = schema.parse(raw);
    const backend = new URL(p.backendOrigin),
        activation = new URL(p.activationUrl);
    check(
        backend.href === backend.origin + '/' &&
            !backend.username &&
            !backend.password,
        'INVALID_PROFILE',
    );
    const loopback = (url) =>
        url.protocol === 'http:' &&
        ['127.0.0.1', '[::1]'].includes(url.hostname);
    check(
        p.kind === 'canonical'
            ? backend.protocol === 'https:' && activation.protocol === 'https:'
            : loopback(backend) &&
                  loopback(activation) &&
                  backend.origin === activation.origin,
        'INVALID_PROFILE',
    );
    check(
        !activation.username && !activation.password && !activation.hash,
        'INVALID_PROFILE',
    );
    // Public keys only. Do not accept a privileged executor as an operator.
    if (p.publicApiKey.startsWith('ey')) {
        let claims;
        try {
            claims = JSON.parse(
                Buffer.from(p.publicApiKey.split('.')[1], 'base64url'),
            );
        } catch {
            check(false, 'INVALID_PROFILE');
        }
        check(claims.role === 'anon', 'INVALID_PROFILE');
    } else
        check(
            p.publicApiKey.startsWith('sb_publishable_') ||
                p.kind === 'disposable-local',
            'INVALID_PROFILE',
        );
    check(
        p.canonicalProfileSha256 ===
            canonicalBackendProfileSha256({
                tenantId: p.tenantId,
                canonicalOrigin: backend.origin,
                canonicalAnonKey: p.publicApiKey,
                canonicalOrganizationId: p.organizationId,
            }),
        'INVALID_PROFILE',
    );
    return Object.freeze({ ...p, binding: digest(JSON.stringify(p)) });
}
export async function privateRoot(root) {
    check(isAbsolute(root), 'INVALID_PROFILE');
    await mkdir(root, { recursive: true, mode: 0o700 });
    const stat = await lstat(root);
    check(
        !stat.isSymbolicLink() &&
            stat.isDirectory() &&
            (stat.mode & 0o077) === 0 &&
            (!process.getuid || stat.uid === process.getuid()),
        'INSECURE_CONFIG_DIRECTORY',
    );
}
export async function loadProfile(name, root = configHome()) {
    nameSchema.parse(name);
    await privateRoot(root);
    const file = join(root, 'profiles', name + '.json');
    check(!(await lstat(file)).isSymbolicLink(), 'INVALID_PROFILE');
    const p = parseProfile(JSON.parse(await readFile(file, 'utf8')));
    check(p.name === name, 'INVALID_PROFILE');
    return p;
}
export async function importProfile(file, root = configHome()) {
    const p = parseProfile(JSON.parse(await readFile(file, 'utf8')));
    await privateRoot(root);
    const dir = join(root, 'profiles');
    await mkdir(dir, { recursive: true, mode: 0o700 });
    const destination = join(dir, p.name + '.json');
    // Exclusive creation avoids silently rebinding an existing profile/session.
    const handle = await open(destination, 'wx', 0o600);
    try {
        const { binding, ...data } = p;
        await handle.writeFile(JSON.stringify(data, null, 2) + '\n');
    } finally {
        await handle.close();
    }
    return p;
}
export function boundedFetch(fetchImpl = fetch) {
    return async (input, init = {}) => {
        const response = await fetchImpl(input, {
            ...init,
            redirect: 'error',
            signal: AbortSignal.any([
                AbortSignal.timeout(30000),
                ...(init.signal ? [init.signal] : []),
            ]),
        });
        const chunks = [];
        let size = 0;
        if (response.body)
            for await (const chunk of response.body) {
                size += chunk.length;
                check(size <= 20 * 1024 * 1024, 'UPSTREAM_CONTRACT_FAILURE');
                chunks.push(chunk);
            }
        return new Response(Buffer.concat(chunks), {
            status: response.status,
            headers: response.headers,
        });
    };
}
export async function verifyActivation(profile, fetchImpl) {
    const response = await fetchImpl(profile.activationUrl, {
        headers: { 'cache-control': 'no-cache' },
    });
    check(response.ok, 'TARGET_MISMATCH');
    const bytes = Buffer.from(await response.arrayBuffer());
    check(digest(bytes) === profile.activationSha256, 'TARGET_MISMATCH');
    const value = JSON.parse(bytes.toString());
    check(
        Object.keys(value).sort().join(',') ===
            'backend,generation,schemaVersion,tenantId' &&
            value.schemaVersion === 1 &&
            value.tenantId === profile.tenantId &&
            value.generation === profile.generation &&
            value.backend === 'canonical',
        'TARGET_MISMATCH',
    );
}
