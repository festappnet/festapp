import { APP_VERSION } from './version.js';

export class AppConfig {
    static version = APP_VERSION;
    static appName = 'Hvězda Mořská';
    static appTitleShort = 'Hvězda Mořská';
    static supabaseUrl = 'https://lwfpdjxsdmkfyrzqbrlk.supabase.co';
    static anonKey = 'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6Imx3ZnBkanhzZG1rZnlyenFicmxrIiwicm9sZSI6ImFub24iLCJpYXQiOjE3MTEyMjgwNDksImV4cCI6MjAyNjgwNDA0OX0.440P3yf8ZqNjOHEQTn9uJhkKyObhD_7PZ2NwaE9e4J0';
    static backendActivationTenantId = 'hvezdamorska';
    static backendActivationManifestUrl = 'https://hvezdamorska.festapp.net/backend-activation.json';
    static backendActivationCanonicalManifestSha256 = '8076f2555f4769df58fb6a55446856a5a9ccbf4db34129f34712068c9ea8be40';
    static backendActivationCanonicalSupabaseUrl = 'https://api.festapp.net';
    static backendActivationCanonicalAnonKey = 'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJyb2xlIjoiYW5vbiIsImlzcyI6InN1cGFiYXNlIiwiaWF0IjoxNzg3OTA4NjQyLCJleHAiOjE5NDU1ODg2NDJ9.uE20X1ueXZlul4F1fRfV5wXFVlGd8QKBFUHMIo1XD4M';
    static backendActivationCanonicalOrganizationId = 7;
    static backendActivationCanonicalProfileSha256 = '9dd6c445717a6ab8f53c99691365ec9caf5816ac426a2d7fecb0ee1c81e7920f';
    static organization = 4;
    static forceOccasionLink = null;
    static isAllUnit = true;
    static isAppSupported = true;
    static flutterAppUrl = '';
    static webLink = "https://hvezdamorska.festapp.net";
    static privacyUrl = "https://hvezdamorska.festapp.net/privacy/";
    static privacyChoicesUrl = "https://hvezdamorska.festapp.net/privacy/choices/";
    static termsUrl = "https://hvezdamorska.festapp.net/terms/";
    static supportUrl = "https://hvezdamorska.festapp.net/support/";
    static deleteAccountUrl = "https://hvezdamorska.festapp.net/delete-account/";
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
