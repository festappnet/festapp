import { APP_VERSION } from './version.js';

export class AppConfig {
    static version = APP_VERSION;
    static appName = 'vstupenky.online';
    static appTitleShort = 'vstupenky.online';
    static supabaseUrl = 'https://kjdpmixlnhntmxjedpxh.supabase.co';
    static anonKey = 'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6ImtqZHBtaXhsbmhudG14amVkcHhoIiwicm9sZSI6ImFub24iLCJpYXQiOjE3MDE5NDI5NzEsImV4cCI6MjAxNzUxODk3MX0.06nTXCL-i1GxLckfEyCNlVVwt62QTzKUezqmsYSR_MI';
    static backendActivationTenantId = 'festapptickets';
    static backendActivationManifestUrl = 'https://vstupenky.online/backend-activation.json';
    static backendActivationCanonicalManifestSha256 = 'c964ba8e23a79e0a082a280d0a44fe3a424b5168eae0853f33d34c630b1cc31c';
    static backendActivationCanonicalSupabaseUrl = 'https://api.festapp.net';
    static backendActivationCanonicalAnonKey = 'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJyb2xlIjoiYW5vbiIsImlzcyI6InN1cGFiYXNlIiwiaWF0IjoxNzg3OTA4NjQyLCJleHAiOjE5NDU1ODg2NDJ9.uE20X1ueXZlul4F1fRfV5wXFVlGd8QKBFUHMIo1XD4M';
    static backendActivationCanonicalOrganizationId = 3;
    static backendActivationCanonicalProfileSha256 = '40ca6bdd5461d29f4497b41d08c86494ee03e71d98ba7903d632348b3ba13c4e';
    static organization = 3;
    static forceOccasionLink = null;
    static isAllUnit = false;
    static isAppSupported = false;
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
