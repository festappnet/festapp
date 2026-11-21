import { AppConfig } from '../app_config.js';
import { SupabaseService } from './supabase_service.js';

const encode = bytes => btoa(String.fromCharCode(...new Uint8Array(bytes)))
    .replaceAll('+', '-').replaceAll('/', '_').replace(/=+$/, '');
const decode = value => Uint8Array.from(atob(value.replaceAll('-', '+').replaceAll('_', '/')), char => char.charCodeAt(0));
const codePattern = /^[A-Za-z0-9_-]{43}$/;

export class PasskeyService {
    static credentialSupport() {
        return Boolean(globalThis.isSecureContext && globalThis.PublicKeyCredential && globalThis.navigator?.credentials?.get);
    }

    static channel() {
        return {
            clientId: `${AppConfig.organization}:web:${window.location.origin}`,
            organization: AppConfig.organization,
            redirectUri: new URL('/google-auth', window.location.origin).href,
        };
    }

    static async methods() {
        if (!SupabaseService.endpoint) return {};
        const channel = this.channel();
        const query = new URLSearchParams({
            client_id: channel.clientId,
            organization: channel.organization,
            redirect_uri: channel.redirectUri,
        });
        try {
            const { methods } = await this.request(`festapp/mfa/channel?${query}`);
            return methods ?? {};
        } catch {
            return {};
        }
    }

    static async capability() {
        if (!this.credentialSupport()) return false;
        const { passkey } = await this.methods();
        return passkey?.offer === true && passkey.signIn === true;
    }

    static supportsRegistration() {
        return this.credentialSupport() && typeof navigator.credentials.create === 'function';
    }

    static async request(path, body, { signal, token } = {}) {
        const headers = {};
        if (body !== undefined) headers['Content-Type'] = 'application/json';
        if (token) {
            headers.Authorization = `Bearer ${token}`;
            headers.apikey = SupabaseService._backend.anonKey;
        }
        const response = await fetch(new URL(`/auth/v1/${path}`, SupabaseService.endpoint), {
            method: body === undefined ? 'GET' : 'POST',
            headers,
            body: body === undefined ? undefined : JSON.stringify(body),
            credentials: 'omit',
            cache: 'no-store',
            redirect: 'error',
            signal,
        });
        if (!response.ok) {
            const error = await response.json().catch(() => ({}));
            throw new Error(error.code || 'passkey_operation_failed');
        }
        return response.json();
    }

    static async assertion(options, signal) {
        const input = { ...options, userVerification: 'required' };
        const publicKey = PublicKeyCredential.parseRequestOptionsFromJSON?.(input) ?? {
            ...input,
            challenge: decode(input.challenge),
            allowCredentials: input.allowCredentials?.map(item => ({ ...item, id: decode(item.id) })),
        };
        const credential = await navigator.credentials.get({ publicKey, signal });
        if (!credential) throw new Error('passkey_operation_failed');
        if (typeof credential.toJSON === 'function') return credential.toJSON();
        const { response } = credential;
        return {
            id: credential.id,
            rawId: encode(credential.rawId),
            type: credential.type,
            authenticatorAttachment: credential.authenticatorAttachment,
            clientExtensionResults: credential.getClientExtensionResults(),
            response: {
                authenticatorData: encode(response.authenticatorData),
                clientDataJSON: encode(response.clientDataJSON),
                signature: encode(response.signature),
                userHandle: response.userHandle === null ? null : encode(response.userHandle),
            },
        };
    }

    static async creation(options, signal) {
        const input = { ...options, authenticatorSelection: {
            ...options.authenticatorSelection, userVerification: 'required',
        } };
        const publicKey = PublicKeyCredential.parseCreationOptionsFromJSON?.(input) ?? {
            ...input,
            challenge: decode(input.challenge),
            user: { ...input.user, id: decode(input.user.id) },
            excludeCredentials: input.excludeCredentials?.map(item => ({ ...item, id: decode(item.id) })),
        };
        const credential = await navigator.credentials.create({ publicKey, signal });
        if (!credential) throw new Error('passkey_operation_failed');
        if (typeof credential.toJSON === 'function') return credential.toJSON();
        return {
            id: credential.id, rawId: encode(credential.rawId), type: credential.type,
            authenticatorAttachment: credential.authenticatorAttachment,
            clientExtensionResults: credential.getClientExtensionResults(),
            response: {
                attestationObject: encode(credential.response.attestationObject),
                clientDataJSON: encode(credential.response.clientDataJSON),
                transports: credential.response.getTransports?.() ?? [],
            },
        };
    }

    static callbackCode(callback, channel, name) {
        const returned = new URL(callback);
        const code = returned.searchParams.get(name);
        if (!codePattern.test(code) || [...returned.searchParams].length !== 1) throw new Error('invalid_passkey_handoff');
        returned.search = '';
        if (returned.href !== channel.redirectUri || AppConfig.organization !== channel.organization) {
            throw new Error('invalid_passkey_handoff');
        }
        return code;
    }

    static async pkce() {
        const codeVerifier = encode(crypto.getRandomValues(new Uint8Array(32)));
        const codeChallenge = encode(await crypto.subtle.digest('SHA-256', new TextEncoder().encode(codeVerifier)));
        return { codeVerifier, codeChallenge };
    }

    static async storedPasskeys(settings) {
        if (!SupabaseService.endpoint) return null;
        try {
            const result = await this.request('festapp/passkey/manage/list', {}, settings);
            return Array.isArray(result) ? result : null;
        } catch {
            return null;
        }
    }

    static async registrationReceipt(method, settings, recoveryCode) {
        const channel = this.channel();
        const { codeVerifier, codeChallenge } = await this.pkce();
        const { callback } = await this.request('festapp/mfa/registration/start', {
            ...channel, method, codeChallenge, inPlace: true, ...(recoveryCode ? { recoveryCode } : {}),
        }, settings);
        const code = this.callbackCode(callback, channel, 'mfa_code');
        const receipt = await this.request('festapp/mfa/registration/claim', {
            organization: channel.organization, code, codeVerifier, ...(recoveryCode ? { recovery: true } : {}),
        }, settings);
        if (receipt.method !== method) throw new Error('invalid_passkey_handoff');
        return receipt.id;
    }

    static async enrollWebAuthn(receipt, settings, checkSession, recovery = false) {
        const request = path => `festapp/mfa/webauthn/${path}`;
        const enrollment = { receipt, ...(recovery ? { recovery: true } : {}) };
        const factor = await this.request(request('enroll'), enrollment, settings);
        const scope = { ...enrollment, factorId: factor.id };
        const options = await this.request(request('challenge'), scope, settings);
        if (options.webauthn?.type !== 'create') throw new Error('invalid_webauthn_challenge');
        const credential = await this.creation(options.webauthn.credential_options.publicKey, settings.signal);
        settings.signal?.throwIfAborted();
        await checkSession();
        return this.request(request('verify'), { ...scope, challengeId: options.id, credential }, settings);
    }

    static async signIn(signal) {
        const channel = this.channel();
        const settings = { signal };
        const { codeVerifier, codeChallenge } = await this.pkce();
        const { challenge_id, options } = await this.request('festapp/passkey/sign-in/options', {
            ...channel, codeChallenge,
        }, settings);
        const credential = await this.assertion(options, signal);
        const { callback } = await this.request('festapp/passkey/sign-in/verify', {
            challengeId: challenge_id, credential,
        }, settings);
        const code = this.callbackCode(callback, channel, 'passkey_code');
        return this.request('festapp/passkey/sign-in/exchange', {
            clientId: channel.clientId, organization: channel.organization, code, codeVerifier,
        }, settings);
    }
}
