import { randomUUID } from 'node:crypto';
import { mkdir, readFile, open, rename, unlink, lstat } from 'node:fs/promises';
import { join, dirname } from 'node:path';
import { digest, privateRoot } from '../context/profile.mjs';
import { check } from '../errors.mjs';
import {
    canonical,
    pendingIntentSchema,
    fingerprintDraft,
} from './layout-contract.mjs';
// The SessionOwner profile lock must cover claim, submission and compare-and-clear.
// This is client recovery state; SQL receipts remain the idempotency authority.
export class FileIntentStore {
    constructor(root) {
        this.root = root;
    }
    async path(profile, userId, occasionId) {
        await privateRoot(this.root);
        const dir = join(this.root, 'pending-layouts');
        await mkdir(dir, { recursive: true, mode: 0o700 });
        return join(
            dir,
            digest(JSON.stringify([profile.binding, userId, occasionId])) +
                '.json',
        );
    }
    async read(profile, userId, occasionId) {
        const path = await this.path(profile, userId, occasionId);
        try {
            const stat = await lstat(path);
            check(
                stat.isFile() &&
                    !stat.isSymbolicLink() &&
                    stat.size <= 100000 &&
                    (stat.mode & 0o077) === 0,
                'PENDING_RECOVERY_REQUIRED',
            );
            const parsed = pendingIntentSchema.safeParse(
                JSON.parse(await readFile(path, 'utf8')),
            );
            check(parsed.success, 'PENDING_RECOVERY_REQUIRED');
            const intent = parsed.data;
            check(
                intent.profileBinding === profile.binding &&
                    intent.userId === userId &&
                    intent.request.occasionId === occasionId,
                'PENDING_RECOVERY_REQUIRED',
            );
            check(
                fingerprintDraft(profile.binding, intent.request) ===
                    intent.request.draftFingerprint,
                'PENDING_RECOVERY_REQUIRED',
            );
            return intent;
        } catch (error) {
            if (error.code === 'ENOENT') return null;
            throw error;
        }
    }
    async claim(profile, userId, request) {
        const existing = await this.read(profile, userId, request.occasionId);
        if (existing) {
            check(
                JSON.stringify(canonical(existing.request)) ===
                    JSON.stringify(canonical(request)),
                'PENDING_RECOVERY_REQUIRED',
            );
            return existing;
        }
        const intent = {
            schemaVersion: 1,
            profileBinding: profile.binding,
            userId,
            commandId: randomUUID(),
            createdAt: new Date().toISOString(),
            request: structuredClone(request),
        };
        const path = await this.path(profile, userId, request.occasionId),
            temporary = path + '.' + randomUUID();
        const file = await open(temporary, 'wx', 0o600);
        try {
            await file.writeFile(JSON.stringify(intent));
            await file.sync();
        } finally {
            await file.close();
        }
        try {
            await rename(temporary, path);
            await this.syncDirectory(path);
        } catch (error) {
            await unlink(temporary).catch(() => {});
            throw error;
        }
        return intent;
    }
    async clear(profile, userId, occasionId, commandId) {
        const current = await this.read(profile, userId, occasionId);
        if (!current || current.commandId !== commandId) return false;
        const path = await this.path(profile, userId, occasionId);
        await unlink(path);
        await this.syncDirectory(path);
        return true;
    }
    async syncDirectory(path) {
        const file = await open(dirname(path), 'r');
        try {
            await file.sync();
        } finally {
            await file.close();
        }
    }
}
