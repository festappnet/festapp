import { APP_VERSION } from './version.js';

export class AppConfig {
    static version = APP_VERSION;
    static appName = 'CSA 2024';
    static appTitleShort = 'CSA 2024';
    static supabaseUrl = 'https://lwfpdjxsdmkfyrzqbrlk.supabase.co';
    static anonKey = 'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6Imx3ZnBkanhzZG1rZnlyenFicmxrIiwicm9sZSI6ImFub24iLCJpYXQiOjE3MTEyMjgwNDksImV4cCI6MjAyNjgwNDA0OX0.440P3yf8ZqNjOHEQTn9uJhkKyObhD_7PZ2NwaE9e4J0';
    static backendActivationTenantId = 'aksmcz';
    static backendActivationManifestUrl = 'https://csa2024.festapp.net/backend-activation.json';
    static backendActivationCanonicalManifestSha256 = 'd8bcc9e0ad2d521534355f68d85015cfcbaeae59386c4d07e27becefc00e304b';
    static backendActivationCanonicalSupabaseUrl = 'https://api.festapp.net';
    static backendActivationCanonicalAnonKey = 'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJyb2xlIjoiYW5vbiIsImlzcyI6InN1cGFiYXNlIiwiaWF0IjoxNzg3OTA4NjQyLCJleHAiOjE5NDU1ODg2NDJ9.uE20X1ueXZlul4F1fRfV5wXFVlGd8QKBFUHMIo1XD4M';
    static backendActivationCanonicalOrganizationId = 4;
    static backendActivationCanonicalProfileSha256 = 'fe382d4bc495a477e7477020e3aa77fee88a1d7cdfdf97f63c6eac06e2d715f3';
    static organization = 1;
    static forceOccasionLink = "csa2024";
    static isAllUnit = false;
    static isAppSupported = true;
    static flutterAppUrl = '';
    static webLink = "https://csa2024.festapp.net";
    static privacyUrl = "https://csa2024.festapp.net/privacy/";
    static privacyChoicesUrl = "https://csa2024.festapp.net/privacy/choices/";
    static termsUrl = "https://csa2024.festapp.net/terms/";
    static supportUrl = "https://csa2024.festapp.net/support/";
    static deleteAccountUrl = "https://csa2024.festapp.net/delete-account/";
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
