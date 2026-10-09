import { browserStorage } from './browser_storage.js';
import { SupabaseService } from './supabase_service.js';
import { AppConfig } from '../app_config.js';
import { RightsService } from './rights_service.js';
import { RouterService } from './router_service.js';

export class AuthService {
    static REFRESH_TOKEN_KEY = 'refresh'; // Typically handled by Supabase JS automatically, but we might mirror logic if needed.
    // Supabase JS handles session persistence in localStorage by default given the config in SupabaseService.

    static async login(email, password) {
        const { data, error } = await SupabaseService.getClient().auth.signInWithPassword({
            email: email,
            password: password,
        });

        if (error) {
            throw error;
        }

        // Trigger updates
        await this._onLoginSuccess();
        return data;
    }

    static async logout() {
        await SupabaseService.getClient().auth.signOut();
        // Clear local data if needed
        browserStorage.removeItem(SupabaseService.tokenKey);
        // Reset Rights
        // (RightsService usually listens to auth state changes, but we force it here too)
        await RightsService.updateAppData(); 
        
        // Redirect to homepage/root which will handle default routing
        RouterService.openExternalUrl('/', { inCurrentWindow: true });
    }

    static async register(data) {
        // data comes from form: { email, password, firstName, lastName, ... }
        // The Flutter app calls a specific Supabase Function "register"
        // static Future<Map<String, dynamic>> register(Map<String, dynamic> data) async {
        //     data["organization"] = AppConfig.organization;
        //     var resp = await _supabase.functions.invoke("register", body: data);
        //     return resp.data;
        // }
        
        const body = { 
            ...data, 
            organization: AppConfig.organization 
        };

        const { data: responseData, error } = await SupabaseService.getClient().functions.invoke('register', {
            body: body
        });

        if (error) {
            throw error;
        }
        
        // The edge function usually returns { code: 200, ... } or throws error
        if (responseData && responseData.code !== 200) {
             throw new Error(responseData.message || "Registration failed");
        }

        return responseData;
    }

    static async resetPasswordForEmail(email) {
        // static Future<dynamic> resetPasswordForEmail(String email) async {
        //   return await _supabase.functions.invoke("send-reset-password-link", body: {"email": email, "organization": AppConfig.organization});
        // }
        const { data, error } = await SupabaseService.getClient().functions.invoke('send-reset-password-link', {
            body: { 
                email: email, 
                organization: AppConfig.organization 
            }
        });

        if (error) {
            throw error;
        }
        return data;
    }
    
    // Internal helper to refresh app state after login
    static async _onLoginSuccess() {
        // In Flutter: 
        // DbEvents.synchronizeMySchedule(join: true);
        // SynchroService.refreshOfflineData();
        
        // In Web:
        // We mostly just need to ensure RightsService picks up the new user
        await RightsService.updateAppData();
    }
    
    static async changePassword(token, password) {
        // static Future<dynamic> changePassword(String token, String pw) async {
        //   return await _supabase.rpc("set_user_password_token", params: { "token": token, "password": pw });
        // }
        const { data, error } = await SupabaseService.getClient().rpc('set_user_password_token', {
            token: token,
            password: password
        });

        if (error) {
            throw error;
        }
        return data; // Returns { code: 200, email: "..." } or error code
    }

    static async isLoggedIn() {
        const { data, error } = await SupabaseService.getClient().auth.getSession();
        return !error && !!data?.session;
    }

    static async completeExternalLogin(result) {
        const client = SupabaseService.getClient();
        if (result.organization !== AppConfig.organization || !result.userId || !result.session?.refresh_token) throw new Error('account_identity_inconsistent');
        try {
            const { data, error } = await client.auth.setSession(result.session);
            if (error || data.user?.id !== result.userId) throw new Error('account_identity_inconsistent');
            const profile = await client.from('user_info').select('id').eq('id', result.userId).eq('organization', AppConfig.organization).maybeSingle();
            if (profile.error || !profile.data) throw new Error('account_identity_inconsistent');
            await this._onLoginSuccess();
        } catch (error) {
            await client.auth.signOut({ scope: 'local' });
            throw error;
        }
    }
}
