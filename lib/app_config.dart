import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:fstapp/components/_shared/common_strings.dart';
import 'package:fstapp/components/app_management/language_model.dart';
import 'package:fstapp/components/occasion/admin_page.dart';

class AppConfig {
  static const String supabaseUrl = 'https://lwfpdjxsdmkfyrzqbrlk.supabase.co';
  static const String anonKey = 'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6Imx3ZnBkanhzZG1rZnlyenFicmxrIiwicm9sZSI6ImFub24iLCJpYXQiOjE3MTEyMjgwNDksImV4cCI6MjAyNjgwNDA0OX0.440P3yf8ZqNjOHEQTn9uJhkKyObhD_7PZ2NwaE9e4J0';
  static const String effectiveSupabaseUrl = String.fromEnvironment(
    'FESTAPP_SUPABASE_URL',
    defaultValue: supabaseUrl,
  );
  static const String effectiveSupabaseAnonKey = String.fromEnvironment(
    'FESTAPP_SUPABASE_ANON_KEY',
    defaultValue: anonKey,
  );
  static const String supabaseAuthStorageKey = 'sb-lwfpdjxsdmkfyrzqbrlk-auth-token';
  static const String backendActivationTenantId = 'absolventskyvelehrad';
  static const String backendActivationManifestUrl = 'https://app.absolventskyvelehrad.cz/backend-activation.json';
  static const String backendActivationCanonicalManifestSha256 = '252053d6fabfc16eae96e0938e2a2cee1d87b5fe597cb3a44ec21709f166e03e';
  static const String backendActivationCanonicalSupabaseUrl = 'https://api.festapp.net';
  static const String backendActivationCanonicalAnonKey = 'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJyb2xlIjoiYW5vbiIsImlzcyI6InN1cGFiYXNlIiwiaWF0IjoxNzg3OTA4NjQyLCJleHAiOjE5NDU1ODg2NDJ9.uE20X1ueXZlul4F1fRfV5wXFVlGd8QKBFUHMIo1XD4M';
  static const int backendActivationCanonicalOrganizationId = 8;
  static const String backendActivationCanonicalProfileSha256 = 'a6a2ef9d9a467ab58619b6a3cc3e1c128addfe3067b61284139bb33e28ce9841';
  static const String clientSyncTenantId = 'absolventskyvelehrad';
  static const String appName = 'Absolventský Velehrad';
  static String get mapTitle => CommonStrings.map;
  static const bool showPWAInstallOption = true;
  static const bool isOwnProgramSupportedWithoutSignIn = true;
  static const bool isOwnProgramSupported = true;
  static const bool isNotificationsSupported = true;
  static const bool isWebNotificationsSupported = true;
  static const String oneSignalAppId = '236d66f9-f665-49c8-aebb-fe4f857a1f4c';
  static const String oneSignalWebAppId = '236d66f9-f665-49c8-aebb-fe4f857a1f4c';
  static const String pushAppGeneration = 'absolventskyvelehrad_cutover_v2';
  static const String effectivePushAppGeneration = String.fromEnvironment(
    'FESTAPP_PUSH_APP_GENERATION',
    defaultValue: pushAppGeneration,
  );
  static const String logoAsset = 'assets/icons/fstappicon.png';
  static const String darkLogoAsset = 'assets/icons/fstappicon.png';
  static const String programLogoAsset = 'assets/icons/fstappicon.png';
  static const String defaultAdministrationRoute = AdminPage.ROUTE;

  static int organization = 5;
  //setup occasion id to force occasion
  static const String? forceOccasionLink = null;
  static const bool isPublicNotificationSendingDisabled = false;
  static const bool isAllUnit = false;
  static const bool isAppSupported = true;
  static const bool isWebclientSupported = true;
  static const bool isContractFeatureEnabled = false;
  static const bool showBankSupportRole = false;

  static const String webLink = "https://app.absolventskyvelehrad.cz";
  static const String privacyUrl = "https://app.absolventskyvelehrad.cz/privacy/";
  static const String privacyChoicesUrl = "https://app.absolventskyvelehrad.cz/privacy/choices/";
  static const String termsUrl = "https://app.absolventskyvelehrad.cz/terms/";
  static const String supportUrl = "https://app.absolventskyvelehrad.cz/support/";
  static const String deleteAccountUrl = "https://app.absolventskyvelehrad.cz/delete-account/";
  static const String syncHeadOrigin = "https://sync.festapp.net";
  static const String syncAssetOrigin = "https://assets.festapp.net";
  static const String imageApiUrl = 'https://image-api.festapp.net';
  static const String imageProjectId = 'a';
  static bool isProLicense = true;
  static const int imagesMaxWidth = 780;
  static const int imagesMaxBytes = 800000;

  static const int daySplitHour = 4;

  static const bool areAllVolunteersApprovers = false;

  static const bool isFeedbackEnabled = true;
  static const String feedbackEmail = "info@festapp.net";

  static bool isNotificationsCurrentlySupported() {
    if (kIsWeb) {
      return isNotificationsSupported &&
          isWebNotificationsSupported &&
          oneSignalWebAppId.isNotEmpty;
    }
    return isNotificationsSupported && oneSignalAppId.isNotEmpty;
  }

  static List<LanguageModel> availableLanguages() => [
        LanguageModel(const Locale("cs"), "Čeština"),
      ];

  /// This is the single definition place for the prefix structure.
  /// It combines the organization ID and the separator (e.g., "2+").
  static String get _prefixBase => "$organization+";

  static String getUserPrefix(String email) {
    return "$_prefixBase$email";
  }

  static String removeUserPrefix(String emailWithPrefix) {
    if (emailWithPrefix.startsWith(_prefixBase)) {
      return emailWithPrefix.substring(_prefixBase.length);
    }
    return emailWithPrefix;
  }

  static List<String> compatibleUrls() => [AppConfig.webLink];
}
