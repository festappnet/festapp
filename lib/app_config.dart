import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:fstapp/components/_shared/common_strings.dart';
import 'package:fstapp/components/app_management/language_model.dart';
import 'package:fstapp/components/occasion/admin_page.dart';

class AppConfig {
  static const String supabaseUrl = 'https://hvtsoseaywurkmhywdbd.supabase.co';
  static const String anonKey = 'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6Imh2dHNvc2VheXd1cmttaHl3ZGJkIiwicm9sZSI6ImFub24iLCJpYXQiOjE3MTYwMzk1MDYsImV4cCI6MjAzMTYxNTUwNn0.LIFBDLrSxTrI4z_Wwnt_5mS5SW2FC9ysVIhJ3m7FD10';
  static const String effectiveSupabaseUrl = String.fromEnvironment(
    'FESTAPP_SUPABASE_URL',
    defaultValue: supabaseUrl,
  );
  static const String effectiveSupabaseAnonKey = String.fromEnvironment(
    'FESTAPP_SUPABASE_ANON_KEY',
    defaultValue: anonKey,
  );
  static const String supabaseAuthStorageKey = 'sb-hvtsoseaywurkmhywdbd-auth-token';
  static const String backendActivationTenantId = 'festivalslunovrat';
  static const String backendActivationManifestUrl = 'https://slunovrat.festapp.net/backend-activation.json';
  static const String backendActivationCanonicalManifestSha256 = 'f8bb5614c9d40fb2255cdb3dac83da74bf327e41de47341f20ae1bd76fd7be26';
  static const String backendActivationCanonicalSupabaseUrl = 'https://api.festapp.net';
  static const String backendActivationCanonicalAnonKey = 'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJyb2xlIjoiYW5vbiIsImlzcyI6InN1cGFiYXNlIiwiaWF0IjoxNzg3OTA4NjQyLCJleHAiOjE5NDU1ODg2NDJ9.uE20X1ueXZlul4F1fRfV5wXFVlGd8QKBFUHMIo1XD4M';
  static const int backendActivationCanonicalOrganizationId = 19;
  static const String backendActivationCanonicalProfileSha256 = 'e9384a8c6820b5a95122e4804c79e51c70e011da082430ea2a4c5472d99ad9cf';
  static const String appName = 'Slunovrat 2026';
  static String get mapTitle => CommonStrings.map;
  static const bool showPWAInstallOption = true;
  static const bool isOwnProgramSupportedWithoutSignIn = true;
  static const bool isOwnProgramSupported = true;
  static const bool isNotificationsSupported = true;
  static const bool isWebNotificationsSupported = true;
  static const String oneSignalAppId = '4c5b7280-510f-4628-8fb8-b4bdd4fed1b2';
  static const String oneSignalWebAppId = '4c5b7280-510f-4628-8fb8-b4bdd4fed1b2';
  static const String pushAppGeneration = 'festivalslunovrat_cutover_v1';
  static const String effectivePushAppGeneration = String.fromEnvironment(
    'FESTAPP_PUSH_APP_GENERATION',
    defaultValue: pushAppGeneration,
  );
  static const String logoAsset = 'assets/icons/fstapplogo.png';
  static const String darkLogoAsset = 'assets/icons/fstapplogo.png';
  static const String programLogoAsset = 'assets/icons/fstapplogo.png';
  static const String defaultAdministrationRoute = AdminPage.ROUTE;

  static int organization = 1;
  //setup occasion id to force occasion
  static const String? forceOccasionLink = "2025-copy-98cf835a";
  static const bool isPublicNotificationSendingDisabled = false;
  static const bool isAllUnit = false;
  static const bool isAppSupported = true;
  static const bool isWebclientSupported = true;
  static const bool isContractFeatureEnabled = false;
  static const bool showBankSupportRole = false;

  static const String webLink = "https://slunovrat.festapp.net";
  static const String privacyUrl = "https://slunovrat.festapp.net/privacy/";
  static const String privacyChoicesUrl = "https://slunovrat.festapp.net/privacy/choices/";
  static const String termsUrl = "https://slunovrat.festapp.net/terms/";
  static const String supportUrl = "https://slunovrat.festapp.net/support/";
  static const String deleteAccountUrl = "https://slunovrat.festapp.net/delete-account/";
  static const String syncHeadOrigin = "";
  static const String syncAssetOrigin = "";
  static const String imageApiUrl = 'https://image-api.festapp.net';
  static const String imageProjectId = 'slunovrat';
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
