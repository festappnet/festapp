import {AppConfig} from '../../../web_client/src/app_config.js';
import {AuthService} from '../../../web_client/src/services/auth_service.js';
import {PasskeyService} from '../../../web_client/src/services/passkey_service.js';
import {SupabaseService} from '../../../web_client/src/services/supabase_service.js';
import {DbForms} from '../../../web_client/src/components/forms/db_forms.js';
import {WaitlistCommands} from '../../../web_client/src/components/forms/waitlist_commands.js';
import {publicCheckoutLocation} from '../../../web_client/src/utils/public_form_location.js';
import {AccountSecurityPanel} from '../../../web_client/src/components/users/account_security_panel.js';
import '../../../web_client/src/components/users/account_recovery_panel.js';
import {LocalizationService} from '../../../web_client/src/services/localization_service.js';
import english from '../../../assets/translations/en.json';

function configure({organization, anonKey}) {
    AppConfig.organization = organization;
    SupabaseService._backend = {supabaseUrl: window.location.origin, anonKey, organizationId: organization, isCanonical: true};
}

window.qualifyFestappPasskey = async input => {
    const {organization} = input;
    configure(input);
    if (!await PasskeyService.capability()) throw new Error('The optional passkey sign-in action is unavailable');
    const result = await AuthService.loginWithPasskey();
    if (result?.verification) throw new Error('Web login required another factor after the verified passkey');
    const client = SupabaseService.getClient();
    const { data } = await client.rpc('get_account_assurance_v1', {p_organization: organization});
    if (data !== 'allowed') throw new Error('The verified passkey did not unlock account access');
    return {passkeySatisfiesMfa: true};
};

window.mountFestappAccountSecurity = async input => {
    configure(input);
    LocalizationService.currentLocale = 'en';
    LocalizationService.translations = english;
    const client = SupabaseService.getClient();
    const {data, error} = await client.auth.signInWithPassword(input.settingsCredentials);
    if (error || !data.user) throw new Error('Could not sign in to the disposable account settings');
    const panel = new AccountSecurityPanel(client, data.user.id);
    document.body.append(panel.root);
    await panel.load();
    window.festappSettingsSession = async () => Boolean((await client.auth.getSession()).data.session);
};

window.mountFestappRecovery = async input => {
    configure(input);
    LocalizationService.currentLocale = 'en';
    LocalizationService.translations = english;
    const {email, password} = input.recoveryCredentials;
    const {verification} = await AuthService.login(email, password);
    if (!verification?.recovery || !verification.canReplace) {
        throw new Error('Sign-in did not offer the restricted account recovery flow');
    }
    const panel = document.createElement('account-recovery-panel');
    document.body.append(panel);
    panel.open(verification);
    const client = SupabaseService.getClient();
    window.festappRecoveryProof = async () => {
        const held = await client.rpc('get_account_assurance_v1', {p_organization: input.organization});
        const {data} = await client.auth.getSession();
        if (held.data !== 'account_recovery' || !data.session) throw new Error('The recovery screen did not retain a restricted session');
        return data.session.access_token;
    };
};

window.qualifyFestappGuestCheckout = async input => {
    configure(input);
    const client = SupabaseService.getClient();
    const {data, error} = await client.auth.setSession(input.heldSession);
    if (error || !data.session) throw new Error('Could not install the held session');
    const blocked = await client.rpc('get_form_by_link', {input_data: {form_link: input.link}});
    if (blocked.error?.code !== '42501' || blocked.error.message !== 'account_recovery') {
        throw new Error('The account request was not denied by the real assurance hook');
    }
    const form = await DbForms.getFormByLink(input.link);
    if (form?.link !== input.link || !await SupabaseService.requiresGuestCheckout(client, data.session)) {
        throw new Error('The guest checkout did not resolve the public form');
    }
    const orderLink = new URL('/order', window.location.origin);
    orderLink.search = new URLSearchParams({order_id: String(input.orderId), token: input.orderToken});
    if (!publicCheckoutLocation(orderLink)) throw new Error('The customer link would prompt for account verification');
    const commands = new WaitlistCommands();
    const order = await commands.overview({orderId: input.orderId, token: input.orderToken});
    if (order.root?.id !== input.orderId || order.root.state !== 'paid') throw new Error('Guest overview did not load the paid order');
    let invalidCapabilityRejected = false;
    try { await commands.overview({orderId: input.orderId, token: '0'.repeat(64)}); }
    catch (error) { invalidCapabilityRejected = error.message === 'OVERVIEW_UNAVAILABLE'; }
    if (!invalidCapabilityRejected) throw new Error('An invalid customer capability gained access');
    const admin = await commands.clientFor({admin: true}).rpc('get_order_overview_admin_context', {p_order_id: input.orderId});
    if (admin.error?.code !== '42501' || admin.error.message !== 'account_recovery') {
        throw new Error('The limited operator must still pass account assurance');
    }
    const current = await client.auth.getSession();
    if (current.data.session?.access_token !== data.session.access_token) {
        throw new Error('The public transport changed the recovery session');
    }
    return {guestCheckoutWithHeldSession: true, paidCustomerLinkWithHeldSession: true};
};
