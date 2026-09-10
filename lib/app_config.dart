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
  static const String supabaseAuthStorageKey = 'sb-kjdpmixlnhntmxjedpxh-auth-token';
  static const String backendActivationTenantId = 'cavfotofest';
  static const String backendActivationManifestUrl = 'https://clovekavira.festapp.net/backend-activation.json';
  static const String backendActivationCanonicalManifestSha256 = '73e8b36a947bf7ac31996e9e2ef2eff1db117ca5a704ffeab99f4b9d5fa7d5f5';
  static const String backendActivationCanonicalSupabaseUrl = 'https://api.festapp.net';
  static const String backendActivationCanonicalAnonKey = 'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJyb2xlIjoiYW5vbiIsImlzcyI6InN1cGFiYXNlIiwiaWF0IjoxNzg3OTA4NjQyLCJleHAiOjE5NDU1ODg2NDJ9.uE20X1ueXZlul4F1fRfV5wXFVlGd8QKBFUHMIo1XD4M';
  static const int backendActivationCanonicalOrganizationId = 6;
  static const String backendActivationCanonicalProfileSha256 = '078dddedcecf4ab46a503bd0f3bc25e17f05d931baaa4eafb6712d8c447fdaea';
  static const String clientSyncTenantId = 'cavfotofest';
  static const String appName = 'Člověk a víra';
  static String get mapTitle => CommonStrings.map;
  static const bool showPWAInstallOption = true;
  static const bool isOwnProgramSupportedWithoutSignIn = true;
  static const bool isOwnProgramSupported = true;
  static const bool isNotificationsSupported = true;
  static const bool isWebNotificationsSupported = true;
  static const String oneSignalAppId = '009d3437-d794-459f-9e3d-4bd70b740f7d';
  static const String oneSignalWebAppId = '009d3437-d794-459f-9e3d-4bd70b740f7d';
  static const String pushAppGeneration = 'cavfotofest_cutover_v1';
  static const String effectivePushAppGeneration = String.fromEnvironment(
    'FESTAPP_PUSH_APP_GENERATION',
    defaultValue: pushAppGeneration,
  );
  static const String logoAsset = 'assets/icons/fstapplogo.svg';
  static const String darkLogoAsset = 'assets/icons/fstapplogo.dark.svg';
  static const String programLogoAsset = 'assets/icons/fstapplogo.svg';
  static const String defaultAdministrationRoute = AdminPage.ROUTE;

  static int organization = 3;
  //setup occasion id to force occasion
  static const String? forceOccasionLink = null;
  static const bool isPublicNotificationSendingDisabled = false;
  static const bool isAllUnit = false;
  static const bool isAppSupported = true;
  static const bool isWebclientSupported = true;
  static const bool isContractFeatureEnabled = false;
  static const bool showBankSupportRole = false;

  static const String webLink = "https://clovekavira.festapp.net";
  static const String privacyUrl = "https://clovekavira.festapp.net/privacy/";
  static const String privacyChoicesUrl = "https://clovekavira.festapp.net/privacy/choices/";
  static const String termsUrl = "https://clovekavira.festapp.net/terms/";
  static const String supportUrl = "https://clovekavira.festapp.net/support/";
  static const String deleteAccountUrl = "https://clovekavira.festapp.net/delete-account/";
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
