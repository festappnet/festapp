import { APP_VERSION } from './version.js';

export class AppConfig {
    static version = APP_VERSION;
    static appName = 'BISCUP';
    static appTitleShort = 'BISCUP';
    static supabaseUrl = 'https://lwfpdjxsdmkfyrzqbrlk.supabase.co';
    static anonKey = 'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6Imx3ZnBkanhzZG1rZnlyenFicmxrIiwicm9sZSI6ImFub24iLCJpYXQiOjE3MTEyMjgwNDksImV4cCI6MjAyNjgwNDA0OX0.440P3yf8ZqNjOHEQTn9uJhkKyObhD_7PZ2NwaE9e4J0';
    static backendActivationTenantId = 'doobiscup';
    static backendActivationManifestUrl = 'https://biscup.festapp.net/backend-activation.json';
    static backendActivationCanonicalManifestSha256 = '37910cd71e9a1ec4d5136f720534dfc2a32ec4f8bcec8e1b92046ba69d500d95';
    static backendActivationCanonicalSupabaseUrl = 'https://api.festapp.net';
    static backendActivationCanonicalAnonKey = 'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJyb2xlIjoiYW5vbiIsImlzcyI6InN1cGFiYXNlIiwiaWF0IjoxNzg3OTA4NjQyLCJleHAiOjE5NDU1ODg2NDJ9.uE20X1ueXZlul4F1fRfV5wXFVlGd8QKBFUHMIo1XD4M';
    static backendActivationCanonicalOrganizationId = 5;
    static backendActivationCanonicalProfileSha256 = 'bd7e96c00da3c4535355a10e72db81cbc04e38e9b19fc4232edd988824d1df4f';
    static organization = 2;
    static forceOccasionLink = null;
    static isAllUnit = false;
    static isAppSupported = true;
    static flutterAppUrl = '';
    static webLink = "https://biscup.festapp.net";
    static privacyUrl = "https://biscup.festapp.net/privacy/";
    static privacyChoicesUrl = "https://biscup.festapp.net/privacy/choices/";
    static termsUrl = "https://biscup.festapp.net/terms/";
    static supportUrl = "https://biscup.festapp.net/support/";
    static deleteAccountUrl = "https://biscup.festapp.net/delete-account/";
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
