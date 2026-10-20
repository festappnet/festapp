import { mkdir, rmdir } from 'node:fs/promises';
import { join } from 'node:path';
import { setTimeout as delay } from 'node:timers/promises';
import { createClient } from '@supabase/supabase-js';
import {
    configHome,
    privateRoot,
    boundedFetch,
    verifyActivation,
} from '../context/profile.mjs';
import { check, OperationError, upstream } from '../errors.mjs';

function authenticationError(error) {
    if (error && [400, 401].includes(Number(error.status))) {
        throw new OperationError('AUTHENTICATION_REQUIRED');
    }
    upstream(error);
}

export class KeychainStore {
    async entry(binding) {
        check(process.platform === 'darwin', 'SECURE_STORAGE_UNAVAILABLE');
        const { AsyncEntry } = await import('@napi-rs/keyring');
        return new AsyncEntry('net.festapp.operator.v1', binding);
    }
    async read(binding) {
        try {
            const value = await (
                await this.entry(binding)
            ).getPassword(AbortSignal.timeout(10000));
            return value ? JSON.parse(value) : null;
        } catch {
            throw new OperationError('SECURE_STORAGE_UNAVAILABLE');
        }
    }
    async write(binding, value) {
        try {
            await (
                await this.entry(binding)
            ).setPassword(JSON.stringify(value), AbortSignal.timeout(10000));
        } catch {
            throw new OperationError('SECURE_STORAGE_UNAVAILABLE');
        }
    }
    async remove(binding) {
        try {
            await (
                await this.entry(binding)
            ).deletePassword(AbortSignal.timeout(10000));
        } catch {
            throw new OperationError('SECURE_STORAGE_UNAVAILABLE');
        }
    }
}
export class SessionOwner {
    constructor(
        profile,
        {
            store = new KeychainStore(),
            root = configHome(),
            fetchImpl = fetch,
        } = {},
    ) {
        this.profile = profile;
        this.store = store;
        this.root = root;
        this.fetch = boundedFetch(fetchImpl);
    }
    async locked(action) {
        await privateRoot(this.root);
        const dir = join(this.root, 'locks');
        await mkdir(dir, { recursive: true, mode: 0o700 });
        const path = join(dir, this.profile.binding);
        const deadline = Date.now() + 10000;
        while (true) {
            try {
                await mkdir(path, { mode: 0o700 });
                break;
            } catch (error) {
                if (error.code !== 'EEXIST') throw error;
                if (Date.now() >= deadline)
                    throw new OperationError('SESSION_BUSY', true);
                await delay(50);
            }
        }
        try {
            return await action();
        } finally {
            await rmdir(path);
        }
    }
    client(accessToken) {
        return createClient(
            this.profile.backendOrigin,
            this.profile.publicApiKey,
            {
                auth: {
                    persistSession: false,
                    autoRefreshToken: false,
                    detectSessionInUrl: false,
                },
                global: { fetch: this.fetch, ...(accessToken ? { headers: { Authorization: `Bearer ${accessToken}` } } : {}) },
            },
        );
    }
    async identity(client, expectedUser, accessToken) {
        const { data, error } = await client.auth.getUser(accessToken);
        authenticationError(error);
        check(data.user, 'AUTHENTICATION_REQUIRED');
        if (expectedUser)
            check(data.user.id === expectedUser, 'AUTHENTICATION_REQUIRED');
        const assurance =
            await client.auth.mfa.getAuthenticatorAssuranceLevel(accessToken);
        upstream(assurance.error);
        const requiresMfa =
            assurance.data?.nextLevel === 'aal2' ||
            data.user.factors?.some((factor) => factor.status === 'verified');
        check(
            !requiresMfa || assurance.data?.currentLevel === 'aal2',
            'MFA_REQUIRED',
        );
        const user = await client
            .from('user_info')
            .select('id,organization')
            .eq('id', data.user.id)
            .single();
        upstream(user.error);
        check(
            user.data?.id === data.user.id &&
                user.data.organization === this.profile.organizationId,
            'TARGET_MISMATCH',
        );
        return data.user.id;
    }
    // First-party proof is transient; the browser's refresh token is never adopted.
    async withAccessToken(accessToken, action) {
        check(typeof accessToken === 'string' && accessToken.length < 8192, 'AUTHENTICATION_REQUIRED');
        await verifyActivation(this.profile, this.fetch);
        const client = this.client(accessToken);
        const userId = await this.identity(client, undefined, accessToken);
        return action(client, { userId });
    }
    async adoptSession(session, expectedUser) {
        return this.locked(async () => {
            await verifyActivation(this.profile, this.fetch);
            check(session?.access_token && session?.refresh_token && expectedUser, 'AUTHENTICATION_REQUIRED');
            const client = this.client();
            const { data, error } = await client.auth.setSession(session);
            authenticationError(error);
            const userId = await this.identity(client, expectedUser);
            await this.store.write(this.profile.binding, { userId, refreshToken: data.session.refresh_token });
            return { userId };
        });
    }
    async login(email, password) {
        return this.locked(async () => {
            await verifyActivation(this.profile, this.fetch);
            const client = this.client();
            const { data, error } = await client.auth.signInWithPassword({
                email,
                password,
            });
            authenticationError(error);
            check(data.session?.refresh_token, 'AUTHENTICATION_REQUIRED');
            const userId = await this.identity(client);
            await this.store.write(this.profile.binding, {
                userId,
                refreshToken: data.session.refresh_token,
            });
            return { userId };
        });
    }
    async authorized(action) {
        return this.locked(async () => {
            await verifyActivation(this.profile, this.fetch);
            const saved = await this.store.read(this.profile.binding);
            check(
                saved?.userId && saved?.refreshToken,
                'AUTHENTICATION_REQUIRED',
            );
            const client = this.client();
            const { data, error } = await client.auth.refreshSession({
                refresh_token: saved.refreshToken,
            });
            authenticationError(error);
            check(
                data.session?.refresh_token && data.user?.id === saved.userId,
                'AUTHENTICATION_REQUIRED',
            );
            // Preserve rotation even when a subsequent authorization/read is denied.
            await this.store.write(this.profile.binding, {
                userId: saved.userId,
                refreshToken: data.session.refresh_token,
            });
            const userId = await this.identity(client, saved.userId);
            return action(client, { userId, profile: this.profile });
        });
    }
    async logout() {
        return this.locked(() => this.store.remove(this.profile.binding));
    }
}
