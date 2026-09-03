import { APP_VERSION } from './version.js';

export class AppConfig {
    static version = APP_VERSION;
    static appName = 'Rezervace Farnost Opava';
    static appTitleShort = 'Farnost Opava';
    static supabaseUrl = 'https://lwfpdjxsdmkfyrzqbrlk.supabase.co';
    static anonKey = 'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6Imx3ZnBkanhzZG1rZnlyenFicmxrIiwicm9sZSI6ImFub24iLCJpYXQiOjE3MTEyMjgwNDksImV4cCI6MjAyNjgwNDA0OX0.440P3yf8ZqNjOHEQTn9uJhkKyObhD_7PZ2NwaE9e4J0';
    static backendActivationTenantId = 'farnostopava';
    static backendActivationManifestUrl = 'https://farnostopava.festapp.net/backend-activation.json';
    static backendActivationCanonicalManifestSha256 = 'a86d20d3fd185ccf0152db0f67a43dc09fe2752b3264c1a62efd5dcc64017fd8';
    static backendActivationCanonicalSupabaseUrl = 'https://api.festapp.net';
    static backendActivationCanonicalAnonKey = 'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJyb2xlIjoiYW5vbiIsImlzcyI6InN1cGFiYXNlIiwiaWF0IjoxNzg3OTA4NjQyLCJleHAiOjE5NDU1ODg2NDJ9.uE20X1ueXZlul4F1fRfV5wXFVlGd8QKBFUHMIo1XD4M';
    static backendActivationCanonicalOrganizationId = 11;
    static backendActivationCanonicalProfileSha256 = '8c2b245e4b4893562a75761ed2bfb5e6ce629bba00a99b23a21c9e808faf60e1';
    static organization = 8;
    static forceOccasionLink = null;
    static isAllUnit = false;
    static isAppSupported = false;
    static flutterAppUrl = '';
    static webLink = "https://farnostopava.festapp.net";
    static privacyUrl = "https://farnostopava.festapp.net/privacy/";
    static privacyChoicesUrl = "https://farnostopava.festapp.net/privacy/choices/";
    static termsUrl = "https://farnostopava.festapp.net/terms/";
    static supportUrl = "https://farnostopava.festapp.net/support/";
    static deleteAccountUrl = "https://farnostopava.festapp.net/delete-account/";
    static imageApiUrl = 'https://image-api.festapp.net';
    static imageProjectId = 'a';
    static compatibleUrls = [AppConfig.webLink];

    
    // Localization
    static supportedLanguages = ['cs', 'en'];
    static defaultLanguage = 'cs';

    // Local Storage Keys
    static Keys = {
        theme: 'theme',
        locale: 'locale',
        auth: 'sb-lwfpdjxsdmkfyrzqbrlk-auth-token'
    };
}
