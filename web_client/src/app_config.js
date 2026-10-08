import { APP_VERSION } from './version.js';

export class AppConfig {
    static version = APP_VERSION;
    static appName = 'Jubileum mládeže 2025';
    static appTitleShort = 'Jubileum 2025';
    static supabaseUrl = 'https://lwfpdjxsdmkfyrzqbrlk.supabase.co';
    static anonKey = 'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6Imx3ZnBkanhzZG1rZnlyenFicmxrIiwicm9sZSI6ImFub24iLCJpYXQiOjE3MTEyMjgwNDksImV4cCI6MjAyNjgwNDA0OX0.440P3yf8ZqNjOHEQTn9uJhkKyObhD_7PZ2NwaE9e4J0';
    static backendActivationTenantId = 'jubileum2025';
    static backendActivationManifestUrl = 'https://jubileum2025.festapp.net/backend-activation.json';
    static backendActivationCanonicalManifestSha256 = 'ae7383096dd7d4abc545c730bd0a749994322a3b9be9841a21e2208fa3f288d1';
    static backendActivationCanonicalSupabaseUrl = 'https://api.festapp.net';
    static backendActivationCanonicalAnonKey = 'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJyb2xlIjoiYW5vbiIsImlzcyI6InN1cGFiYXNlIiwiaWF0IjoxNzg3OTA4NjQyLCJleHAiOjE5NDU1ODg2NDJ9.uE20X1ueXZlul4F1fRfV5wXFVlGd8QKBFUHMIo1XD4M';
    static backendActivationCanonicalOrganizationId = 9;
    static backendActivationCanonicalProfileSha256 = '6477caf5d836f0cd4e32020deb35a714fa1e526a7db95b04138c6051ed5f4bf1';
    static organization = 6;
    static forceOccasionLink = "jm2025";
    static isAllUnit = false;
    static isAppSupported = true;
    static flutterAppUrl = '';
    static webLink = "https://jubileum2025.festapp.net";
    static privacyUrl = "https://jubileum2025.festapp.net/privacy/";
    static privacyChoicesUrl = "https://jubileum2025.festapp.net/privacy/choices/";
    static termsUrl = "https://jubileum2025.festapp.net/terms/";
    static supportUrl = "https://jubileum2025.festapp.net/support/";
    static deleteAccountUrl = "https://jubileum2025.festapp.net/delete-account/";
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
