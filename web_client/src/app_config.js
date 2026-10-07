import { APP_VERSION } from './version.js';

export class AppConfig {
    static version = APP_VERSION;
    static appName = 'Absolventský Velehrad';
    static appTitleShort = 'AV';
    static supabaseUrl = 'https://lwfpdjxsdmkfyrzqbrlk.supabase.co';
    static anonKey = 'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6Imx3ZnBkanhzZG1rZnlyenFicmxrIiwicm9sZSI6ImFub24iLCJpYXQiOjE3MTEyMjgwNDksImV4cCI6MjAyNjgwNDA0OX0.440P3yf8ZqNjOHEQTn9uJhkKyObhD_7PZ2NwaE9e4J0';
    static backendActivationTenantId = 'absolventskyvelehrad';
    static backendActivationManifestUrl = 'https://app.absolventskyvelehrad.cz/backend-activation.json';
    static backendActivationCanonicalManifestSha256 = '252053d6fabfc16eae96e0938e2a2cee1d87b5fe597cb3a44ec21709f166e03e';
    static backendActivationCanonicalSupabaseUrl = 'https://api.festapp.net';
    static backendActivationCanonicalAnonKey = 'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJyb2xlIjoiYW5vbiIsImlzcyI6InN1cGFiYXNlIiwiaWF0IjoxNzg3OTA4NjQyLCJleHAiOjE5NDU1ODg2NDJ9.uE20X1ueXZlul4F1fRfV5wXFVlGd8QKBFUHMIo1XD4M';
    static backendActivationCanonicalOrganizationId = 8;
    static backendActivationCanonicalProfileSha256 = 'a6a2ef9d9a467ab58619b6a3cc3e1c128addfe3067b61284139bb33e28ce9841';
    static organization = 5;
    static forceOccasionLink = null;
    static isAllUnit = false;
    static isAppSupported = true;
    static flutterAppUrl = '';
    static webLink = "https://app.absolventskyvelehrad.cz";
    static privacyUrl = "https://app.absolventskyvelehrad.cz/privacy/";
    static privacyChoicesUrl = "https://app.absolventskyvelehrad.cz/privacy/choices/";
    static termsUrl = "https://app.absolventskyvelehrad.cz/terms/";
    static supportUrl = "https://app.absolventskyvelehrad.cz/support/";
    static deleteAccountUrl = "https://app.absolventskyvelehrad.cz/delete-account/";
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
