import { SupabaseService } from './supabase_service.js';
import { AppConfig } from '../app_config.js';
import { LocalizationService } from './localization_service.js';

export class RightsService {
    static _context = null;
    static _listeners = [];

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
        // Simple caching logic: if we have context and not forcing, maybe skip?
        // But for now, let's just fetch to be safe and ensure fresh rights.
        
        // Mirror Flutter rights_service.dart: forceOccasionLink overrides when no explicit link given.
        const effectiveLink = link || AppConfig.forceOccasionLink || null;

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
                console.error("RightsService: Error fetching app config", error);
                return false;
            }

            // Rights updates can also originate from auth and router flows, not
            // only from Main. Never publish renderable context until the shared
            // translation dictionary is ready.
            await LocalizationService.init();
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
        return this.isUnitEditorView() || this.isEditorOrderView();
    }
    
    static isEditorOrderView() {
        return this.occasionUser?.is_editor_order_view === true;
    }
    
    static isUnitEditorView() {
        return this._context?.unit_user?.is_editor_view === true;
    }

    static isAdmin() {
        return !!this._context?.is_admin;
    }

    static isEditor() {
        return !!this.occasionUser?.is_editor;
    }

    static isManager() {
        return !!this.occasionUser?.is_manager;
    }

    static isUnitManager() {
        return !!this._context?.unit_user?.is_manager;
    }


    static canSeeAdmin() {
        const admin = this.isAdmin();
        const editor = this.isEditor();
        const manager = this.isManager();
        const unitEditorView = this.isUnitEditorView();
        const hasUnits = this.hasUnits();
        return admin || editor || manager || unitEditorView || hasUnits;
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
