import { browserStorage } from './browser_storage.js';
import { SupabaseService } from './supabase_service.js';
import { AppConfig } from '../app_config.js';
import { RightsService } from './rights_service.js';
import { PasskeyService } from './passkey_service.js';
import { RouterService } from './router_service.js';

export class AuthService {
    static REFRESH_TOKEN_KEY = 'refresh'; // Typically handled by Supabase JS automatically, but we might mirror logic if needed.
    // Supabase JS handles session persistence in localStorage by default given the config in SupabaseService.

    static async login(email, password) {
        const client = SupabaseService.getClient();
        const { data, error } = await client.auth.signInWithPassword({
            email: email,
            password: password,
        });

        if (error) {
            throw error;
        }

        const verification = await this._verificationFor(client, data.session);
        if (verification) return { ...data, verification };
        await this._onLoginSuccess();
        return data;
    }

    static async _verificationFor(client, session) {
        if (!session?.user?.id || !await this._matchesSession(client, session)) throw new Error('invalid_session');
        const organization = AppConfig.organization;
        const { data, error } = await client.rpc('get_account_assurance_v1', {
            p_organization: organization,
        });
        if (organization !== AppConfig.organization || !await this._matchesSession(client, session)) throw new Error('invalid_session');
        if (error) throw new Error('assurance_unavailable');
        if (data === 'allowed') return null;
        RightsService.clearCapabilities();
        if (data === 'account_recovery') {
            const actor = await client.rpc('get_mfa_recovery_registration_actor_v1', { p_organization: organization });
            if (organization !== AppConfig.organization || !await this._matchesSession(client, session)) throw new Error('invalid_session');
            return { session, recovery: true, organization, canReplace: actor.data?.decision === 'allowed' };
        }
        if (data !== 'mfa_required' && data !== 'proof_required') throw new Error('invalid_session');
        const factors = await client.auth.mfa.listFactors();
        if (factors.error) throw new Error('assurance_unavailable');
        if (!await this._matchesSession(client, session)) throw new Error('invalid_session');
        const totp = factors.data?.totp ?? [];
        const webauthn = PasskeyService.credentialSupport() ? factors.data?.webauthn ?? [] : [];
        if (!totp.length && !webauthn.length) throw new Error('mfa_factor_unavailable');
        return { session, factors: totp, webauthn };
    }

    static async _matchesSession(client, session) {
        const { data, error } = await client.auth.getSession();
        return Boolean(session?.access_token) && !error && data.session?.access_token === session.access_token;
    }

    static async resumeVerification() {
        const client = SupabaseService.getClient();
        const { data, error } = await client.auth.getSession();
        if (error || !data.session) return null;
        return this._verificationFor(client, data.session);
    }

    static async verifyLogin(verification, factorId, code) {
        const client = SupabaseService.getClient();
        if (!await this._matchesSession(client, verification.session)) throw new Error('invalid_session');
        if (!/^\d{6}$/.test(code) || !verification.factors.some(factor => factor.id === factorId)) throw new Error('invalid_mfa_code');
        const { data, error } = await client.auth.mfa.challengeAndVerify({ factorId, code });
        if (error) throw new Error('invalid_mfa_code');
        await this._finishVerification(client, verification, data);
    }

    static async verifyWebAuthn(verification, factorId, signal) {
        const client = SupabaseService.getClient();
        if (!verification.webauthn?.some(factor => factor.id === factorId) ||
            !await this._matchesSession(client, verification.session)) throw new Error('invalid_session');
        const settings = { signal, token: verification.session.access_token };
        const factorPath = `factors/${encodeURIComponent(factorId)}`;
        const challenge = await PasskeyService.request(`${factorPath}/challenge`, {}, settings);
        if (challenge.webauthn?.type !== 'request') throw new Error('invalid_webauthn_challenge');
        const credential = await PasskeyService.assertion(challenge.webauthn.credential_options.publicKey, signal);
        signal?.throwIfAborted();
        if (!await this._matchesSession(client, verification.session)) throw new Error('invalid_session');
        const upgraded = await PasskeyService.request(`${factorPath}/verify`, {
            challenge_id: challenge.id,
            webauthn: { type: 'request', credential_response: credential },
        }, settings);
        signal?.throwIfAborted();
        if (!await this._matchesSession(client, verification.session)) throw new Error('invalid_session');
        const { error } = await client.auth.setSession({
            access_token: upgraded.access_token, refresh_token: upgraded.refresh_token,
        });
        if (error) throw error;
        await this._finishVerification(client, verification, upgraded);
    }

    static async _finishVerification(client, verification, data) {
        const { data: installed } = await client.auth.getSession();
        if (installed.session?.access_token !== data?.access_token ||
            installed.session?.user?.id !== verification.session.user.id ||
            await this._verificationFor(client, installed.session)) {
            throw new Error('invalid_session');
        }
        await this._onLoginSuccess();
    }

    static async cancelVerification(verification) {
        if (!verification) return;
        const client = SupabaseService.getClient();
        if (await this._matchesSession(client, verification.session)) {
            await client.auth.signOut({ scope: 'local' });
            RightsService.clearCapabilities();
        }
    }

    static async requireRecoverySession(verification) {
        const client = SupabaseService.getClient();
        if (!verification?.recovery || verification.organization !== AppConfig.organization ||
            !await this._matchesSession(client, verification.session)) throw new Error('invalid_session');
        return client;
    }

    static async installRecoveryReplacement(verification, upgraded) {
        const client = await this.requireRecoverySession(verification);
        const { data, error } = await client.auth.setSession({
            access_token: upgraded.access_token, refresh_token: upgraded.refresh_token,
        });
        if (error || data?.session?.user?.id !== verification.session.user.id) throw new Error('invalid_session');
        await this.requireRecoverySession({ ...verification, session: data.session });
        const held = await client.rpc('get_account_assurance_v1', { p_organization: verification.organization });
        if (held.data !== 'account_recovery') throw new Error('invalid_session');
        await this.requireRecoverySession({ ...verification, session: data.session });
    }

    static async logout() {
        RightsService.clearCapabilities();
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
             const failure = new Error(responseData.message || responseData.error || "Registration failed");
             failure.code = responseData.code;
             throw failure;
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
        if (!await RightsService.updateAppData()) throw new Error('account_context_unavailable');
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

    static async loginWithPasskey(signal) {
        const client = SupabaseService.getClient();
        const requireAnonymous = async () => {
            signal?.throwIfAborted();
            const { data, error } = await client.auth.getSession();
            if (error || data?.session) throw new Error('invalid_session');
        };
        await requireAnonymous();
        const result = await PasskeyService.signIn(signal);
        await requireAnonymous();
        return this._installExternalLogin(result, true);
    }

    static async completeExternalLogin(result) {
        await this._installExternalLogin(result, false);
    }

    static async _installExternalLogin(result, allowVerification) {
        const client = SupabaseService.getClient();
        if (result.organization !== AppConfig.organization || !result.userId || !result.session?.refresh_token) throw new Error('account_identity_inconsistent');
        let session;
        try {
            const { data, error } = await client.auth.setSession(result.session);
            session = data?.session;
            if (error || data.user?.id !== result.userId) throw new Error('account_identity_inconsistent');
            const verification = await this._verificationFor(client, session);
            if (verification) {
                if (allowVerification) return { verification };
                throw new Error('mfa_required');
            }
            const profile = await client.from('user_info').select('id').eq('id', result.userId).eq('organization', AppConfig.organization).maybeSingle();
            if (profile.error || !profile.data) throw new Error('account_identity_inconsistent');
            await this._onLoginSuccess();
        } catch (error) {
            if (await this._matchesSession(client, session)) await client.auth.signOut({ scope: 'local' });
            throw error;
        }
    }
}
