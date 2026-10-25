import { APP_VERSION } from './version.js';

export class AppConfig {
  static organizerLandingEnabled = true;
    static maxTicketsPerOrder = 20;
    static version = APP_VERSION;
    static appName = 'Festapp Tickets';
    static appTitleShort = 'Festapp Tickets';
    static supabaseUrl = 'https://kjdpmixlnhntmxjedpxh.supabase.co';
    static anonKey = 'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6ImtqZHBtaXhsbmhudG14amVkcHhoIiwicm9sZSI6ImFub24iLCJpYXQiOjE3MDE5NDI5NzEsImV4cCI6MjAxNzUxODk3MX0.06nTXCL-i1GxLckfEyCNlVVwt62QTzKUezqmsYSR_MI';
    static backendActivationTenantId = 'festappticketsglobal';
    static backendActivationManifestUrl = 'https://tickets.festapp.net/backend-activation.json';
    static backendActivationCanonicalManifestSha256 = '3a1ac8b7d50b65f01efbd7039304f72df4cec8dacfab1f973992db9b9a966f38';
    static backendActivationCanonicalSupabaseUrl = 'https://api.festapp.net';
    static backendActivationCanonicalAnonKey = 'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJyb2xlIjoiYW5vbiIsImlzcyI6InN1cGFiYXNlIiwiaWF0IjoxNzg3OTA4NjQyLCJleHAiOjE5NDU1ODg2NDJ9.uE20X1ueXZlul4F1fRfV5wXFVlGd8QKBFUHMIo1XD4M';
    static backendActivationCanonicalOrganizationId = 25;
    static backendActivationCanonicalProfileSha256 = '8a4cecc2be882a394af56441cc0651103784de62f1bb782fe0d11d372aea8f75';
    static organization = 25;
    static forceOccasionLink = null;
    static isAllUnit = false;
    static isAppSupported = false;
    static flutterAppUrl = '';
    static webLink = "https://tickets.festapp.net";
    static privacyUrl = "https://tickets.festapp.net/privacy/";
    static privacyChoicesUrl = "https://tickets.festapp.net/privacy/choices/";
    static termsUrl = "https://tickets.festapp.net/terms/";
    static supportUrl = "https://tickets.festapp.net/support/";
    static deleteAccountUrl = "https://tickets.festapp.net/delete-account/";
    static imageApiUrl = 'https://image-api.festapp.net';
    static imageProjectId = 'default';
    static compatibleUrls = [AppConfig.webLink];

    
    // Localization
    static supportedLanguages = ['en'];
    static defaultLanguage = 'en';

    // Local Storage Keys
    static Keys = {
        theme: 'theme',
        locale: 'locale',
        auth: 'sb-festappticketsglobal-auth-token'
    };
}
