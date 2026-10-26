import { AppConfig } from '../app_config.js';

const hex = (bytes) => [...new Uint8Array(bytes)]
    .map((value) => value.toString(16).padStart(2, '0'))
    .join('');

export class BackendActivationService {
    static schemaVersion = 1;
    static canonicalGeneration = 1;
    static markerPrefix = 'festapp-backend-activation-v1:';
    static canonicalMarker = 'canonical:1';

    constructor({ config = AppConfig, storage,
        fetchImpl = globalThis.fetch?.bind(globalThis), subtle = globalThis.crypto?.subtle } = {}) {
        this.config = config;
        try {
            this.storage = storage === undefined ? globalThis.localStorage : storage;
        } catch (_) {
            this.storage = null;
        }
        this.fetchImpl = fetchImpl;
        this.subtle = subtle;
    }

    get enabled() {
        return Boolean(
            this.config.backendActivationTenantId &&
            this.config.backendActivationManifestUrl &&
            this.config.backendActivationCanonicalManifestSha256 &&
            this.config.backendActivationCanonicalSupabaseUrl &&
            this.config.backendActivationCanonicalAnonKey &&
            Number.isSafeInteger(this.config.backendActivationCanonicalOrganizationId) &&
            this.config.backendActivationCanonicalOrganizationId > 0 &&
            /^[0-9a-f]{64}$/.test(this.config.backendActivationCanonicalProfileSha256)
        );
    }

    async resolve() {
        if (!this.enabled) return this.legacy;
        const markerKey = BackendActivationService.markerPrefix +
            this.config.backendActivationTenantId;
        if (!this.storage) return this.legacy;
        try {
            if (this.storage.getItem(markerKey) === BackendActivationService.canonicalMarker) {
                return this.canonical;
            }
        } catch (_) {
            return this.legacy;
        }
        if (!this.fetchImpl || !this.subtle) return this.legacy;

        let timeoutId;
        try {
            const response = await Promise.race([
                this.fetchImpl(
                    `${this.config.backendActivationManifestUrl}?activation=${Date.now()}`,
                    { cache: 'no-store', headers: { 'cache-control': 'no-cache' } },
                ),
                new Promise((_, reject) => {
                    timeoutId = setTimeout(
                        () => reject(new Error('Backend activation lookup timed out')), 2000,
                    );
                }),
            ]);
            if (!response.ok) return this.legacy;
            const bytes = await response.arrayBuffer();
            const digest = hex(await this.subtle.digest('SHA-256', bytes));
            if (digest !== this.config.backendActivationCanonicalManifestSha256) {
                return this.legacy;
            }
            const value = JSON.parse(new TextDecoder().decode(bytes));
            if (Object.keys(value).length !== 4 ||
                value.schemaVersion !== BackendActivationService.schemaVersion ||
                value.tenantId !== this.config.backendActivationTenantId ||
                value.generation !== BackendActivationService.canonicalGeneration ||
                value.backend !== 'canonical') {
                return this.legacy;
            }
            this.storage.setItem(markerKey, BackendActivationService.canonicalMarker);
            if (this.storage.getItem(markerKey) !== BackendActivationService.canonicalMarker) {
                return this.legacy;
            }
            return this.canonical;
        } catch (_) {
            return this.legacy;
        } finally {
            clearTimeout(timeoutId);
        }
    }

    get legacy() {
        return Object.freeze({
            supabaseUrl: this.config.supabaseUrl,
            anonKey: this.config.anonKey,
            organizationId: this.config.organization,
            profileSha256: '',
            isCanonical: false,
        });
    }

    get canonical() {
        return Object.freeze({
            supabaseUrl: this.config.backendActivationCanonicalSupabaseUrl,
            anonKey: this.config.backendActivationCanonicalAnonKey,
            organizationId: this.config.backendActivationCanonicalOrganizationId,
            profileSha256: this.config.backendActivationCanonicalProfileSha256,
            isCanonical: true,
        });
    }
}
