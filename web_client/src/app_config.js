import { APP_VERSION } from './version.js';

export class AppConfig {
    static version = APP_VERSION;
    static appName = 'Slunovrat 2026';
    static appTitleShort = 'Slunovrat';
    static supabaseUrl = 'https://hvtsoseaywurkmhywdbd.supabase.co';
    static anonKey = 'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6Imh2dHNvc2VheXd1cmttaHl3ZGJkIiwicm9sZSI6ImFub24iLCJpYXQiOjE3MTYwMzk1MDYsImV4cCI6MjAzMTYxNTUwNn0.LIFBDLrSxTrI4z_Wwnt_5mS5SW2FC9ysVIhJ3m7FD10';
    static backendActivationTenantId = 'festivalslunovrat';
    static backendActivationManifestUrl = 'https://slunovrat.festapp.net/backend-activation.json';
    static backendActivationCanonicalManifestSha256 = 'f8bb5614c9d40fb2255cdb3dac83da74bf327e41de47341f20ae1bd76fd7be26';
    static backendActivationCanonicalSupabaseUrl = 'https://api.festapp.net';
    static backendActivationCanonicalAnonKey = 'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJyb2xlIjoiYW5vbiIsImlzcyI6InN1cGFiYXNlIiwiaWF0IjoxNzg3OTA4NjQyLCJleHAiOjE5NDU1ODg2NDJ9.uE20X1ueXZlul4F1fRfV5wXFVlGd8QKBFUHMIo1XD4M';
    static backendActivationCanonicalOrganizationId = 19;
    static backendActivationCanonicalProfileSha256 = 'e9384a8c6820b5a95122e4804c79e51c70e011da082430ea2a4c5472d99ad9cf';
    static organization = 1;
    static forceOccasionLink = "2025-copy-98cf835a";
    static isAllUnit = false;
    static isAppSupported = true;
    static flutterAppUrl = 'https://slunovrat.festapp.net';
    static webLink = "https://slunovrat.festapp.net";
    static privacyUrl = "https://slunovrat.festapp.net/privacy/";
    static privacyChoicesUrl = "https://slunovrat.festapp.net/privacy/choices/";
    static termsUrl = "https://slunovrat.festapp.net/terms/";
    static supportUrl = "https://slunovrat.festapp.net/support/";
    static deleteAccountUrl = "https://slunovrat.festapp.net/delete-account/";
    static imageApiUrl = 'https://image-api.festapp.net';
    static imageProjectId = 'slunovrat';
    static compatibleUrls = [AppConfig.webLink];

    
    // Localization
    static supportedLanguages = ['cs', 'en', 'pl'];
    static defaultLanguage = 'cs';

    // Local Storage Keys
    static Keys = {
        theme: 'theme',
        locale: 'locale',
        auth: 'sb-hvtsoseaywurkmhywdbd-auth-token'
    };
}
