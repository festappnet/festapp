import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:fstapp/components/_shared/common_strings.dart';
import 'package:fstapp/components/app_management/language_model.dart';
import 'package:fstapp/components/occasion/admin_page.dart';

class AppConfig {
  static const String supabaseUrl = 'https://kjdpmixlnhntmxjedpxh.supabase.co';
  static const String anonKey = 'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6ImtqZHBtaXhsbmhudG14amVkcHhoIiwicm9sZSI6ImFub24iLCJpYXQiOjE3MDE5NDI5NzEsImV4cCI6MjAxNzUxODk3MX0.06nTXCL-i1GxLckfEyCNlVVwt62QTzKUezqmsYSR_MI';
  static const String effectiveSupabaseUrl = String.fromEnvironment(
    'FESTAPP_SUPABASE_URL',
    defaultValue: supabaseUrl,
  );
  static const String effectiveSupabaseAnonKey = String.fromEnvironment(
    'FESTAPP_SUPABASE_ANON_KEY',
    defaultValue: anonKey,
  );
  static const String supabaseAuthStorageKey = 'sb-kjdpmixlnhntmxjedpxh-auth-token';
  static const String backendActivationTenantId = '';
  static const String backendActivationManifestUrl = '';
  static const String backendActivationCanonicalManifestSha256 = '';
  static const String backendActivationCanonicalSupabaseUrl = '';
  static const String backendActivationCanonicalAnonKey = '';
  static const int backendActivationCanonicalOrganizationId = 0;
  static const String backendActivationCanonicalProfileSha256 = '';
  static const String clientSyncTenantId = '';
  static const String appName = 'Festapp';
  static String get mapTitle => CommonStrings.map;
  static const bool showPWAInstallOption = true;
  static const bool isOwnProgramSupportedWithoutSignIn = true;
  static const bool isOwnProgramSupported = true;
  static const bool isNotificationsSupported = true;
  static const bool isWebNotificationsSupported = true;
  static const String oneSignalAppId = '';
  static const String oneSignalWebAppId = '';
  static const String pushAppGeneration = '';
  static const String effectivePushAppGeneration = String.fromEnvironment(
    'FESTAPP_PUSH_APP_GENERATION',
    defaultValue: pushAppGeneration,
  );
  static const String logoAsset = 'assets/icons/fstapplogo.svg';
  static const String darkLogoAsset = 'assets/icons/fstapplogo.dark.svg';
  static const String programLogoAsset = 'assets/icons/fstapplogo.svg';
  static const String defaultAdministrationRoute = AdminPage.ROUTE;

  static int organization = 1;
  //setup occasion id to force occasion
  static const String? forceOccasionLink = null;
  static const bool isPublicNotificationSendingDisabled = false;
  static const bool isAllUnit = false;
  static const bool isAppSupported = true;
  static const bool isWebclientSupported = true;
  static const bool isContractFeatureEnabled = false;
  static const bool showBankSupportRole = false;

  static const String webLink = "https://vstupenky.online";
  static const String privacyUrl = "https://vstupenky.online/privacy/";
  static const String privacyChoicesUrl = "https://vstupenky.online/privacy/choices/";
  static const String termsUrl = "https://vstupenky.online/terms/";
  static const String supportUrl = "https://vstupenky.online/support/";
  static const String deleteAccountUrl = "https://vstupenky.online/delete-account/";
  static const String syncHeadOrigin = "";
  static const String syncAssetOrigin = "";
  static const String imageApiUrl = 'https://image-api.festapp.net';
  static const String imageProjectId = 'default';
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
