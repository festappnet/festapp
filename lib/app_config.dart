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
  static const String backendActivationTenantId = 'farnostopava';
  static const String backendActivationManifestUrl = 'https://farnostopava.festapp.net/backend-activation.json';
  static const String backendActivationCanonicalManifestSha256 = 'a86d20d3fd185ccf0152db0f67a43dc09fe2752b3264c1a62efd5dcc64017fd8';
  static const String backendActivationCanonicalSupabaseUrl = 'https://api.festapp.net';
  static const String backendActivationCanonicalAnonKey = 'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJyb2xlIjoiYW5vbiIsImlzcyI6InN1cGFiYXNlIiwiaWF0IjoxNzg3OTA4NjQyLCJleHAiOjE5NDU1ODg2NDJ9.uE20X1ueXZlul4F1fRfV5wXFVlGd8QKBFUHMIo1XD4M';
  static const int backendActivationCanonicalOrganizationId = 11;
  static const String backendActivationCanonicalProfileSha256 = '8c2b245e4b4893562a75761ed2bfb5e6ce629bba00a99b23a21c9e808faf60e1';
  static const String appName = 'Rezervace Farnost Opava';
  static String get mapTitle => CommonStrings.map;
  static const bool showPWAInstallOption = true;
  static const bool isOwnProgramSupportedWithoutSignIn = true;
  static const bool isOwnProgramSupported = true;
  static const bool isNotificationsSupported = true;
  static const bool isWebNotificationsSupported = true;
  static const String oneSignalAppId = '';
  static const String oneSignalWebAppId = '';
  static const String pushAppGeneration = 'farnostopava_no_push_v1';
  static const String effectivePushAppGeneration = String.fromEnvironment(
    'FESTAPP_PUSH_APP_GENERATION',
    defaultValue: pushAppGeneration,
  );
  static const String logoAsset = 'assets/icons/fstapplogo.svg';
  static const String darkLogoAsset = 'assets/icons/fstapplogo.dark.svg';
  static const String programLogoAsset = 'assets/icons/fstapplogo.svg';
  static const String defaultAdministrationRoute = AdminPage.ROUTE;

  static int organization = 8;
  //setup occasion id to force occasion
  static const String? forceOccasionLink = null;
  static const bool isPublicNotificationSendingDisabled = false;
  static const bool isAllUnit = false;
  static const bool isAppSupported = false;
  static const bool isWebclientSupported = true;
  static const bool isContractFeatureEnabled = false;
  static const bool showBankSupportRole = false;

  static const String webLink = "https://farnostopava.festapp.net";
  static const String privacyUrl = "https://farnostopava.festapp.net/privacy/";
  static const String privacyChoicesUrl = "https://farnostopava.festapp.net/privacy/choices/";
  static const String termsUrl = "https://farnostopava.festapp.net/terms/";
  static const String supportUrl = "https://farnostopava.festapp.net/support/";
  static const String deleteAccountUrl = "https://farnostopava.festapp.net/delete-account/";
  static const String syncHeadOrigin = "";
  static const String syncAssetOrigin = "";
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
