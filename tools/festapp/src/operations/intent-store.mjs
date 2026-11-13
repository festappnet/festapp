import { randomUUID } from 'node:crypto';
import { mkdir, readFile, open, link, unlink, lstat } from 'node:fs/promises';
import { join, dirname } from 'node:path';
import { digest, privateRoot } from '../context/profile.mjs';
import { check } from '../errors.mjs';
import {
    canonical,
    pendingIntentSchema,
    fingerprintDraft,
    layoutCommandId,
} from './layout-contract.mjs';
// The owner recovery lock must cover claim, submission and compare-and-clear.
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
            commandId: layoutCommandId(profile.binding, userId, request.draftFingerprint),
            createdAt: new Date().toISOString(),
            request: structuredClone(request),
        };
        return this.publish(profile, userId, intent);
    }
    async publish(profile, userId, intent) {
        const request = intent.request;
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
            // Atomic no-replace publication: a concurrent claimant must keep
            // the original command UUID even when its payload is identical.
            await link(temporary, path);
            await this.syncDirectory(path);
        } catch (error) {
            if (error.code !== 'EEXIST') throw error;
            const current = await this.read(profile, userId, request.occasionId);
            check(current && JSON.stringify(canonical(current.request)) === JSON.stringify(canonical(request)), 'PENDING_RECOVERY_REQUIRED');
            return current;
        } finally {
            await unlink(temporary).catch(() => {});
        }
        return intent;
    }
    async rebind(previous, profile, userId, occasionId) {
        if (previous.binding === profile.binding) return;
        const original = await this.read(previous, userId, occasionId);
        if (!original) return;
        const request = { ...original.request };
        request.draftFingerprint = fingerprintDraft(profile.binding, request);
        const candidate = { ...original, profileBinding: profile.binding, request };
        const current = await this.read(profile, userId, occasionId);
        check(!current || (current.commandId === original.commandId &&
            JSON.stringify(canonical(current.request)) === JSON.stringify(canonical(request))), 'PENDING_RECOVERY_REQUIRED');
        const retained = current ?? await this.publish(profile, userId, candidate);
        check(retained.commandId === original.commandId, 'PENDING_RECOVERY_REQUIRED');
        await this.clear(previous, userId, occasionId, original.commandId);
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
