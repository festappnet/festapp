import { browserStorage } from './browser_storage.js';
import { AppConfig } from '../app_config.js';
import { createClient } from '@supabase/supabase-js';
import { BackendActivationService } from './backend_activation_service.js';
import { APP_VERSION } from '../version.js';

const restrictedAccountDecisions = new Set([
    'account_recovery', 'factor_change_pending', 'invalid_session', 'mfa_required', 'proof_required',
]);

export class SupabaseService {
    static _client = null;
    static _guest = null;
    static _initialization = null;
    static _backend = null;
    static tokenKey = AppConfig.Keys.auth;
    static originMarkerKey = 'festapp-supabase-auth-origin';
    static clientOptions = Object.freeze({
        auth: Object.freeze({ storageKey: AppConfig.Keys.auth, storage: browserStorage }),
        global: Object.freeze({ headers: Object.freeze({
            'X-Client-Info': `festapp/${APP_VERSION}/js`,
        }) }),
    });

    static async getEmailConfirmationStatus(capability) {
        const {data, error} = await this.getClient().functions.invoke('email-confirmation-status', {body: {capability}});
        if (error) throw error;
        return data;
    }

    static get endpoint() { return SupabaseService._backend?.supabaseUrl ?? null; }
    static get isCanonicalBackend() { return SupabaseService._backend?.isCanonical === true; }

    // A prepared scanner can open its local shell without waiting for an Auth
    // refresh. Online RPCs still pass through initialize() before use.
    static initializeScannerOffline() {
        const activation = new BackendActivationService({ storage: browserStorage });
        const marker = browserStorage.getItem(
            BackendActivationService.markerPrefix + AppConfig.backendActivationTenantId,
        );
        SupabaseService._backend = activation.enabled &&
                marker === BackendActivationService.canonicalMarker
            ? activation.canonical
            : activation.legacy;
        AppConfig.organization = SupabaseService._backend.organizationId;
        return SupabaseService._backend;
    }

    static getClient() {
        if (!SupabaseService._client) {
            if (!SupabaseService._backend) {
                throw new Error('SupabaseService.initialize() must resolve the backend first');
            }
            const backend = SupabaseService._backend;
            SupabaseService._client = createClient(
                backend.supabaseUrl,
                backend.anonKey,
                SupabaseService.clientOptions,
            );
        }
        return SupabaseService._client;
    }

    static getGuestClient() {
        const backend = this._backend;
        if (!backend) throw new Error('SupabaseService.initialize() must resolve the backend first');
        if (this._guest?.backend !== backend) {
            this._guest = {backend, client: createClient(backend.supabaseUrl, backend.anonKey, {
                global: this.clientOptions.global, accessToken: async () => null,
            })};
        }
        return this._guest.client;
    }

    static async publicCheckoutRpc(name, args, signal) {
        const request = client => {
            const rpc = client.rpc(name, args);
            return signal ? rpc.abortSignal(signal) : rpc;
        };
        const result = await request(this.getClient());
        // The common pre-request hook rejects before the RPC can run.
        if (result.error?.code === '42501' && restrictedAccountDecisions.has(result.error.message)) {
            return request(this.getGuestClient());
        }
        return result;
    }

    static async requiresGuestCheckout(client, session) {
        if (!session || !this.isCanonicalBackend) return false;
        const {data, error} = await client.rpc('get_account_assurance_v1', {
            p_organization: AppConfig.organization,
        }).setHeader('Authorization', `Bearer ${session.access_token}`);
        // A canonical backend can still be preparing its MFA migration.
        if (error?.code === 'PGRST202') return false;
        if (error) throw error;
        if (data === 'allowed') return false;
        if (restrictedAccountDecisions.has(data)) return true;
        throw new Error('PAYMENT_RECOVERY_REQUIRED');
    }

    // Bind the anonymous check to the exact client that owns the request.
    static async isAnonymousClient(client) {
        if (this.getClient() !== client) return false;
        const {data, error} = await client.auth.getSession();
        return !error && data?.session === null && this.getClient() === client;
    }

    /// Refresh an existing browser session exactly when the configured backend
    /// origin changes. The refresh token is preserved by the stable storage
    /// namespace and exchanged for a JWT signed by the new Auth service before
    /// any rights or business query runs.
    static initialize() {
        if (!SupabaseService._initialization) {
            SupabaseService._initialization = SupabaseService._initialize().catch(error => {
                SupabaseService._initialization = null;
                throw error;
            });
        }
        return SupabaseService._initialization;
    }

    static async _initialize() {
        // The signed backend manifest is still verified when persistent storage
        // is blocked; only the activation marker then lives for this page.
        SupabaseService._backend = await new BackendActivationService({ storage: browserStorage }).resolve();
        AppConfig.organization = SupabaseService._backend.organizationId;
        const client = SupabaseService.getClient();
        const activeOrigin = SupabaseService._backend.supabaseUrl;
        const previousOrigin = browserStorage.getItem(SupabaseService.originMarkerKey);
        const { data, error } = await client.auth.getSession();
        if (error) throw error;
        const session = data?.session;
        if (session && previousOrigin !== activeOrigin) {
            const refreshToken = session.refresh_token;
            if (!refreshToken) throw new Error('Stored Supabase session has no refresh token');
            const { data: refreshed, error: refreshError } =
                await client.auth.refreshSession({ refresh_token: refreshToken });
            if (refreshError || !refreshed?.session) {
                if (SupabaseService._isTerminalRefreshError(refreshError)) {
                    try {
                        await client.auth.signOut({ scope: 'local' });
                    } catch (signOutError) {
                        console.warn('Local Supabase session cleanup failed', signOutError);
                    }
                    browserStorage.removeItem(SupabaseService.tokenKey);
                    browserStorage.setItem(SupabaseService.originMarkerKey, activeOrigin);
                    return client;
                }
                throw refreshError ?? new Error('Supabase session refresh returned no session');
            }
        }
        browserStorage.setItem(SupabaseService.originMarkerKey, activeOrigin);
        return client;
    }

    static _isTerminalRefreshError(error) {
        return error?.code === 'refresh_token_not_found' ||
            error?.code === 'refresh_token_already_used';
    }

    // --- Data ---
    // --- Data ---
    // Moved to DbOccasions

    static async signOut() {
        await SupabaseService.getClient().auth.signOut();
        browserStorage.removeItem(SupabaseService.tokenKey);
        window.location.reload();
    }
}
