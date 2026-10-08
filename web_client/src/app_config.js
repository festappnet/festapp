import { APP_VERSION } from './version.js';

export class AppConfig {
    static version = APP_VERSION;
    static appName = 'Člověk a víra';
    static appTitleShort = 'ČaV';
    static supabaseUrl = 'https://lwfpdjxsdmkfyrzqbrlk.supabase.co';
    static anonKey = 'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6Imx3ZnBkanhzZG1rZnlyenFicmxrIiwicm9sZSI6ImFub24iLCJpYXQiOjE3MTEyMjgwNDksImV4cCI6MjAyNjgwNDA0OX0.440P3yf8ZqNjOHEQTn9uJhkKyObhD_7PZ2NwaE9e4J0';
    static backendActivationTenantId = 'cavfotofest';
    static backendActivationManifestUrl = 'https://clovekavira.festapp.net/backend-activation.json';
    static backendActivationCanonicalManifestSha256 = '73e8b36a947bf7ac31996e9e2ef2eff1db117ca5a704ffeab99f4b9d5fa7d5f5';
    static backendActivationCanonicalSupabaseUrl = 'https://api.festapp.net';
    static backendActivationCanonicalAnonKey = 'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJyb2xlIjoiYW5vbiIsImlzcyI6InN1cGFiYXNlIiwiaWF0IjoxNzg3OTA4NjQyLCJleHAiOjE5NDU1ODg2NDJ9.uE20X1ueXZlul4F1fRfV5wXFVlGd8QKBFUHMIo1XD4M';
    static backendActivationCanonicalOrganizationId = 6;
    static backendActivationCanonicalProfileSha256 = '078dddedcecf4ab46a503bd0f3bc25e17f05d931baaa4eafb6712d8c447fdaea';
    static organization = 3;
    static forceOccasionLink = null;
    static isAllUnit = false;
    static isAppSupported = true;
    static flutterAppUrl = '';
    static webLink = "https://clovekavira.festapp.net";
    static privacyUrl = "https://clovekavira.festapp.net/privacy/";
    static privacyChoicesUrl = "https://clovekavira.festapp.net/privacy/choices/";
    static termsUrl = "https://clovekavira.festapp.net/terms/";
    static supportUrl = "https://clovekavira.festapp.net/support/";
    static deleteAccountUrl = "https://clovekavira.festapp.net/delete-account/";
    static imageApiUrl = 'https://image-api.festapp.net';
    static imageProjectId = 'a';
    static compatibleUrls = [AppConfig.webLink];

    
    // Localization
    static supportedLanguages = ['cs', 'en', 'sk', 'pl'];
    static defaultLanguage = 'cs';

    // Local Storage Keys
    static Keys = {
        theme: 'theme',
        locale: 'locale',
        auth: 'sb-kjdpmixlnhntmxjedpxh-auth-token'
    };
}
