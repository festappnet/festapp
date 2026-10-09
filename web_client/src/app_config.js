import { APP_VERSION } from './version.js';

export class AppConfig {
    static version = APP_VERSION;
    static appName = 'vstupenky.online';
    static appTitleShort = 'vstupenky.online';
    static supabaseUrl = 'https://kjdpmixlnhntmxjedpxh.supabase.co';
    static anonKey = 'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6ImtqZHBtaXhsbmhudG14amVkcHhoIiwicm9sZSI6ImFub24iLCJpYXQiOjE3MDE5NDI5NzEsImV4cCI6MjAxNzUxODk3MX0.06nTXCL-i1GxLckfEyCNlVVwt62QTzKUezqmsYSR_MI';
    static backendActivationTenantId = '';
    static backendActivationManifestUrl = '';
    static backendActivationCanonicalManifestSha256 = '';
    static backendActivationCanonicalSupabaseUrl = '';
    static backendActivationCanonicalAnonKey = '';
    static backendActivationCanonicalOrganizationId = 0;
    static backendActivationCanonicalProfileSha256 = '';
    static organization = 1;
    static forceOccasionLink = null;
    static isAllUnit = false;
    static isAppSupported = true;
    static flutterAppUrl = '';
    static webLink = "https://vstupenky.online";
    static privacyUrl = "https://vstupenky.online/privacy/";
    static privacyChoicesUrl = "https://vstupenky.online/privacy/choices/";
    static termsUrl = "https://vstupenky.online/terms/";
    static supportUrl = "https://vstupenky.online/support/";
    static deleteAccountUrl = "https://vstupenky.online/delete-account/";
    static imageApiUrl = 'https://image-api.festapp.net';
    static imageProjectId = 'default';
    static compatibleUrls = [AppConfig.webLink];

    
    // Localization
    static supportedLanguages = ['cs', 'en'];
    static defaultLanguage = 'cs';

    // Local Storage Keys
    static Keys = {
        theme: 'theme',
        locale: 'locale',
        auth: 'sb-kjdpmixlnhntmxjedpxh-auth-token'
    };
}
