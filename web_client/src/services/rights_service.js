import { AuthorizationCapabilities } from './authorization_capabilities.js';
import { SupabaseService } from './supabase_service.js';
import { AppConfig } from '../app_config.js';
import { LocalizationService } from './localization_service.js';

export class RightsService {
    static _context = null;
    static _listeners = [];
    static _requestGeneration = 0;
    static _identityClient = null;
    static _identitySubscription = null;
    static _identityUserId = undefined;
    static _authRefreshTimer = null;
    static _lastRequestOptions = {};

    static clearCapabilities() {
        this._requestGeneration++;
        this._context = null;
        this._notifyListeners();
    }

    static hasCapability(id) {
        return this._context?.capabilities?.[id] === true;
    }

    static get context() {
        return this._context;
    }

    static addListener(callback) {
        this._listeners.push(callback);
    }

    static removeListener(callback) {
        this._listeners = this._listeners.filter(cb => cb !== callback);
    }

    static _notifyListeners() {
        this._listeners.forEach(cb => cb(this._context));
    }

    static async updateAppData({ link = null, unitId = null, formLink = null, force = false } = {}) {
        this._lastRequestOptions = { link, unitId, formLink, force };
        // Simple caching logic: if we have context and not forcing, maybe skip?
        // But for now, let's just fetch to be safe and ensure fresh rights.
        
        // Mirror Flutter rights_service.dart: forceOccasionLink overrides when no explicit link given.
        const effectiveLink = link || AppConfig.forceOccasionLink || null;
        const request = ++this._requestGeneration;
        const organization = AppConfig.organization;
        if (this._context) {
            this._context = { ...this._context, capabilities: {} };
            this._notifyListeners();
        }

        try {
            const client = SupabaseService.getClient();
            if (!client) {
                console.warn("RightsService: Supabase client not initialized. Deferring update.");
                // Retrying after a short delay or just returning false?
                // Since this is likely the first load, let's retry once after a short delay to let Main.init finish.
                return new Promise(resolve => {
                    setTimeout(() => resolve(this.updateAppData({ link, unitId, formLink, force })), 100);
                });
            }

            if (this._identityClient !== client) {
                this._identitySubscription?.unsubscribe();
                clearTimeout(this._authRefreshTimer);
                this._authRefreshTimer = null;
                this._identityUserId = undefined;
                this._identityClient = client;
                this._identitySubscription = client.auth?.onAuthStateChange?.((event, session) => {
                    if (this._identityClient !== client) return;
                    const userId = session?.user?.id ?? null;
                    if (event === 'INITIAL_SESSION') {
                        this._identityUserId = userId;
                        return;
                    }
                    if (event !== 'SIGNED_OUT' && event !== 'SIGNED_IN') return;
                    const sameUser = userId !== null &&
                        (userId === this._identityUserId || userId === this.currentUser?.id);
                    this._identityUserId = userId;
                    // Supabase also emits SIGNED_IN when restoring/refocusing
                    // the same session. Keep its resolved or in-flight context.
                    if (event === 'SIGNED_IN' && sameUser) return;
                    this.clearCapabilities();
                    clearTimeout(this._authRefreshTimer);
                    // Auth callbacks hold the SDK session lock. Fetch outside
                    // that callback, in the latest route's scope, after clearing
                    // private rights and invalidating the old response.
                    this._authRefreshTimer = setTimeout(() => {
                        this._authRefreshTimer = null;
                        if (this._identityClient === client) void this.updateAppData(this._lastRequestOptions);
                    }, 0);
                })?.data?.subscription;
            }
            const { data, error } = await client.rpc('get_app_config_v218', {
                data_in: {
                    link: effectiveLink,
                    form_link: formLink, // Can be null
                    unit_id: unitId,
                    organization: AppConfig.organization || 'festapp',
                    platform: { platform: 'web' }
                }
            });

            if (error) {
                if (request === this._requestGeneration) this.clearCapabilities();
                console.error("RightsService: Error fetching app config", error);
                return false;
            }

            // Rights updates can also originate from auth and router flows, not
            // only from Main. Never publish renderable context until the shared
            // translation dictionary is ready.
            await LocalizationService.init();
            if (request !== this._requestGeneration || organization !== AppConfig.organization) return false;
            this._context = data;
            this._notifyListeners();
            return true;
        } catch (e) {
            console.error("RightsService: Exception fetching app config", e);
            return false;
        }
    }

    // --- User Info Getters ---
    static get currentUser() {
        return this._context?.user_info;
    }

    static get occasionUser() {
        return this._context?.occasion_user;
    }
    
    static get currentLink() {
        return this._context?.occasion?.link;
    }

    static get currentUnit() {
        return this._context?.unit;
    }

    // --- Rights Checks (Mirrors Flutter) ---
    static canSeeReservations() {
        return this.hasCapability(AuthorizationCapabilities.ordersRead);
    }
    
    
    static canSeeAdmin() {
        return this.hasCapability(AuthorizationCapabilities.navigationAdminWeb);
    }

    static hasUnits() {
        return (this.currentUser?.units?.length || 0) > 0;
    }

    /**
     * Helper to safely extract user display info
     * @param {Object} user - The user object
     * @returns {{ name: string, email: string, initial: string }}
     */
    static getUserDisplayInfo(user) {
        if (!user) return { name: '', email: '', initial: '?' };

        // Email: extract from deep structure or readonly field
        const email = user.email_readonly || (user.data && user.data.email) || user.email || '';
        
        // Name
        const name = `${user.name || ''} ${user.surname || ''}`.trim();

        // Initial
        const initial = (user.name || email || '?').charAt(0).toUpperCase();

        return { name, email, initial };
    }
}
