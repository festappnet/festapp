import { browserStorage } from './browser_storage.js';
import { AppConfig } from '../app_config.js';
import { createClient } from '@supabase/supabase-js';
import { BackendActivationService } from './backend_activation_service.js';
import { APP_VERSION } from '../version.js';

export class SupabaseService {
    static _client = null;
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

    /// Refresh an existing browser session exactly when the configured backend
    /// origin changes. The refresh token is preserved by the stable storage
    /// namespace and exchanged for a JWT signed by the new Auth service before
    /// any rights or business query runs.
    static initialize() {
        if (!SupabaseService._initialization) {
            SupabaseService._initialization = SupabaseService._initialize();
        }
        return SupabaseService._initialization;
    }

    static async _initialize() {
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

    // --- Auth ---
    static getLocalUser() {
        const localSessionStr = browserStorage.getItem(SupabaseService.tokenKey);
        if (localSessionStr) {
            try {
                const sessionData = JSON.parse(localSessionStr);
                return sessionData.user;
            } catch (e) {
                console.error("Error parsing local session", e);
            }
        }
        return null;
    }

    static async validateSession() {
        // Background check
        const { data, error } = await SupabaseService.getClient().auth.getSession();
        if (error || !data.session) {
            // Invalid, clear local
            browserStorage.removeItem(SupabaseService.tokenKey);
            return null;
        }
        return data.session.user;
    }

    static async signOut() {
        await SupabaseService.getClient().auth.signOut();
        browserStorage.removeItem(SupabaseService.tokenKey);
        window.location.reload();
    }
}
