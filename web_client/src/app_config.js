import { APP_VERSION } from './version.js';

export class AppConfig {
    static version = APP_VERSION;
    static appName = 'CSM Ostrava';
    static appTitleShort = 'CSM 2026';
    static supabaseUrl = 'https://lwfpdjxsdmkfyrzqbrlk.supabase.co';
    static anonKey = 'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6Imx3ZnBkanhzZG1rZnlyenFicmxrIiwicm9sZSI6ImFub24iLCJpYXQiOjE3MTEyMjgwNDksImV4cCI6MjAyNjgwNDA0OX0.440P3yf8ZqNjOHEQTn9uJhkKyObhD_7PZ2NwaE9e4J0';
    static backendActivationTenantId = 'csmostrava2026';
    static backendActivationManifestUrl = 'https://csmostrava.festapp.net/backend-activation.json';
    static backendActivationCanonicalManifestSha256 = 'd6d1c5236dc23ceed3e3fd7030b65cec3ab77acc7dc7a320413538c1fb7cf561';
    static backendActivationCanonicalSupabaseUrl = 'https://api.festapp.net';
    static backendActivationCanonicalAnonKey = 'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJyb2xlIjoiYW5vbiIsImlzcyI6InN1cGFiYXNlIiwiaWF0IjoxNzg3OTA4NjQyLCJleHAiOjE5NDU1ODg2NDJ9.uE20X1ueXZlul4F1fRfV5wXFVlGd8QKBFUHMIo1XD4M';
    static backendActivationCanonicalOrganizationId = 12;
    static backendActivationCanonicalProfileSha256 = '026308e2c10ea6e8e8b74bae5b54d4f831be7aa84235ce32dba74e7607965ccd';
    static organization = 9;
    static forceOccasionLink = "csmostrava2026";
    static isAllUnit = false;
    static isAppSupported = true;
    static flutterAppUrl = '';
    static webLink = "https://csmostrava.festapp.net";
    static privacyUrl = "https://csmostrava.festapp.net/privacy/";
    static privacyChoicesUrl = "https://csmostrava.festapp.net/privacy/choices/";
    static termsUrl = "https://csmostrava.festapp.net/terms/";
    static supportUrl = "https://csmostrava.festapp.net/support/";
    static deleteAccountUrl = "https://csmostrava.festapp.net/delete-account/";
    static imageApiUrl = 'https://image-api.festapp.net';
    static imageProjectId = 'a';
    static compatibleUrls = [AppConfig.webLink];

    
    // Localization
    static supportedLanguages = ['cs'];
    static defaultLanguage = 'cs';

    // Local Storage Keys
    static Keys = {
        theme: 'theme',
        locale: 'locale',
        auth: 'sb-lwfpdjxsdmkfyrzqbrlk-auth-token'
    };
}
