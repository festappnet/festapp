import { APP_VERSION } from './version.js';

export class AppConfig {
    static version = APP_VERSION;
    static appName = 'Festapp';
    static appTitleShort = 'Festapp';
    static supabaseUrl = 'https://kjdpmixlnhntmxjedpxh.supabase.co';
    static anonKey = 'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6ImtqZHBtaXhsbmhudG14amVkcHhoIiwicm9sZSI6ImFub24iLCJpYXQiOjE3MDE5NDI5NzEsImV4cCI6MjAxNzUxODk3MX0.06nTXCL-i1GxLckfEyCNlVVwt62QTzKUezqmsYSR_MI';
    static backendActivationTenantId = 'festapp';
    static backendActivationManifestUrl = 'https://live.festapp.net/backend-activation.json';
    static backendActivationCanonicalManifestSha256 = '15298165a25a6739f6a53b516552be2ac0faff6362edfb5b9893e5f4a80dd4aa';
    static backendActivationCanonicalSupabaseUrl = 'https://api.festapp.net';
    static backendActivationCanonicalAnonKey = 'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJyb2xlIjoiYW5vbiIsImlzcyI6InN1cGFiYXNlIiwiaWF0IjoxNzg3OTA4NjQyLCJleHAiOjE5NDU1ODg2NDJ9.uE20X1ueXZlul4F1fRfV5wXFVlGd8QKBFUHMIo1XD4M';
    static backendActivationCanonicalOrganizationId = 1;
    static backendActivationCanonicalProfileSha256 = '56c1b82dbff2aa967268c98d95acddd3d156004d6339c19f9b85b0ae49490e4f';
    static organization = 1;
    static forceOccasionLink = null;
    static isAllUnit = false;
    static isAppSupported = true;
    static flutterAppUrl = '';
    static webLink = "https://live.festapp.net";
    static privacyUrl = "https://live.festapp.net/privacy/";
    static privacyChoicesUrl = "https://live.festapp.net/privacy/choices/";
    static termsUrl = "https://live.festapp.net/terms/";
    static supportUrl = "https://live.festapp.net/support/";
    static deleteAccountUrl = "https://live.festapp.net/delete-account/";
    static imageApiUrl = 'https://image-api.festapp.net';
    static imageProjectId = 'default';
    static compatibleUrls = [AppConfig.webLink];

    
    // Localization
    static supportedLanguages = ['cs'];
    static defaultLanguage = 'cs';

    // Local Storage Keys
    static Keys = {
        theme: 'theme',
        locale: 'locale',
        auth: 'sb-kjdpmixlnhntmxjedpxh-auth-token'
    };
}
