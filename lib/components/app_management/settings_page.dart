import 'package:fstapp/data_services/auth_service.dart';
import 'package:fstapp/components/mcp/mcp_connections_link.dart';
import 'package:adaptive_theme/adaptive_theme.dart';
import 'package:auto_route/auto_route.dart';
import 'package:flutter/material.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:fstapp/router_service.dart';
import 'package:fstapp/components/_shared/common_strings.dart';
import 'package:fstapp/components/app_management/app_management_strings.dart';
import 'package:fstapp/components/app_management/language_model.dart';
import 'package:fstapp/components/app_management/pwa_storage_advanced_settings.dart';
import 'package:fstapp/services/dialog_helper.dart';
import 'package:fstapp/services/notification_helper.dart';
import 'package:fstapp/app_config.dart';
import 'package:fstapp/services/platform_helper.dart';
import 'package:fstapp/styles/styles_config.dart';
import 'package:fstapp/theme_config.dart';
import 'package:fstapp/widgets/buttons_helper.dart';
import 'package:pwa_install/pwa_install.dart';
import 'package:flutter/foundation.dart';

@RoutePage()
class SettingsPage extends StatefulWidget {
  static const ROUTE = "settings";
  const SettingsPage({super.key});

  @override
  _SettingsPageState createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage> {
  bool _notificationsEnabled = false;
  bool _isAppInstalled = false;
  bool _isPromptEnabled = false;
  bool _isPlatformSupported = true;
  bool _notificationError = false;
  LanguageModel? _currentLanguage;
  AdaptiveThemeMode? _themeMode;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    loadSettings();
  }

  Future<void> loadSettings() async {
    bool isEnabled = await NotificationHelper.isNotificationOnOff();
    Locale currentLocale = context.locale;
    LanguageModel? currentLanguage = AppConfig.availableLanguages().firstWhere(
        (language) =>
            language.locale.languageCode == currentLocale.languageCode);
    bool isAppInstalled = PlatformHelper.isPwaInstalledOrNative();
    var themeMode = await AdaptiveTheme.getThemeMode();
    setState(() {
      _themeMode = themeMode;
      _notificationsEnabled = isEnabled;
      _currentLanguage = currentLanguage;
      _isAppInstalled = isAppInstalled;
      _isPromptEnabled = PWAInstall().installPromptEnabled;
    });
  }

  Future<void> handleInstallButtonPress() async {
    try {
      PWAInstall().promptInstall_();
    } catch (e) {
      setState(() {
        _isPlatformSupported = false;
      });
    }
    await loadSettings();
  }

  bool get _canInstallPWA =>
      !_isAppInstalled && _isPlatformSupported && _isPromptEnabled;

  void _setThemeMode(AdaptiveThemeMode mode) {
    setState(() {
      _themeMode = mode;
      AdaptiveTheme.of(context).setThemeMode(mode);
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(CommonStrings.settings,
            style: TextStyle(color: ThemeConfig.appBarColorNegative())),
        leading: BackButton(
          onPressed: () => RouterService.goBackOrInitial(context),
          color: ThemeConfig.appBarColorNegative(),
        ),
      ),
      body: Align(
        alignment: Alignment.topCenter,
        child: Padding(
          padding: const EdgeInsets.all(16.0),
          child: ConstrainedBox(
            constraints: BoxConstraints(maxWidth: StylesConfig.appMaxWidth),
            child: SingleChildScrollView(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (AuthService.isLoggedIn()) ...[
                    const McpConnectionsLink(),
                    const SizedBox(height: 24),
                  ],
                  if (AppConfig.availableLanguages().length > 1) ...[
                    Text(CommonStrings.languageSettings,
                        style: const TextStyle(fontSize: 20)),
                    const SizedBox(height: 16),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                          CommonStrings.currentLanguage(
                              language: _currentLanguage?.name ?? '---'),
                          style: const TextStyle(fontSize: 16),
                        ),
                        IconButton(
                          onPressed: () async {
                            await DialogHelper.chooseLanguage(context);
                            await loadSettings();
                          },
                          icon: const Icon(Icons.translate),
                        ),
                      ],
                    ),
                    const SizedBox(height: 24),
                  ],
                  if (AppConfig.isNotificationsCurrentlySupported()) ...[
                    Text(AppManagementStrings.notificationSettings,
                        style: const TextStyle(fontSize: 20)),
                    const SizedBox(height: 16),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(AppManagementStrings.enableNotifications,
                            style: const TextStyle(fontSize: 16)),
                        Switch(
                          value: _notificationsEnabled,
                          onChanged: (value) async {
                            bool success;
                            if (value) {
                              success =
                                  await NotificationHelper.turnNotificationOn();
                            } else {
                              await NotificationHelper.turnNotificationOff();
                              success = true;
                            }
                            if (!success) {
                              setState(() {
                                _notificationError = true;
                              });
                            }
                            await loadSettings();
                          },
                        ),
                      ],
                    ),
                    if (_notificationError)
                      Padding(
                        padding: const EdgeInsets.only(top: 8.0),
                        child: Text(
                          AppManagementStrings.enableNotificationsFailed,
                          style:
                              TextStyle(color: ThemeConfig.redColor(context)),
                          textAlign: TextAlign.center,
                        ),
                      ),
                  ],
                  const SizedBox(height: 24),
                  if (ThemeConfig.isDarkModeEnabled)
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(CommonStrings.appearance,
                            style: const TextStyle(fontSize: 20)),
                        const SizedBox(height: 16),
                        ToggleButtons(
                          isSelected: [
                            _themeMode == AdaptiveThemeMode.dark,
                            _themeMode == AdaptiveThemeMode.system,
                            _themeMode == AdaptiveThemeMode.light,
                          ],
                          onPressed: (int index) {
                            if (index == 0) {
                              _setThemeMode(AdaptiveThemeMode.dark);
                            } else if (index == 1) {
                              _setThemeMode(AdaptiveThemeMode.system);
                            } else if (index == 2) {
                              _setThemeMode(AdaptiveThemeMode.light);
                            }
                          },
                          borderRadius: BorderRadius.circular(8.0),
                          children: [
                            Padding(
                              padding:
                                  const EdgeInsets.symmetric(horizontal: 12.0),
                              child: Text(CommonStrings.dark),
                            ),
                            Padding(
                              padding:
                                  const EdgeInsets.symmetric(horizontal: 12.0),
                              child: Text(CommonStrings.auto),
                            ),
                            Padding(
                              padding:
                                  const EdgeInsets.symmetric(horizontal: 12.0),
                              child: Text(CommonStrings.light),
                            ),
                          ],
                        ),
                        const SizedBox(height: 24),
                      ],
                    ),
                  if (kIsWeb) // Only show if running on web
                    Center(
                      child: Column(
                        children: [
                          ButtonsHelper.bigButton(
                            context: context,
                            label: AppManagementStrings.installApp,
                            onPressed: _canInstallPWA
                                ? handleInstallButtonPress
                                : null,
                            color: _canInstallPWA
                                ? ThemeConfig.blackColor(context)
                                : Colors.grey,
                            textColor: ThemeConfig.whiteColor(context),
                          ),
                          if (!_isAppInstalled &&
                              (!_isPlatformSupported || !_isPromptEnabled))
                            Padding(
                              padding: const EdgeInsets.only(top: 8.0),
                              child: Text(
                                AppManagementStrings.pwaPromptNotSupported,
                                style: TextStyle(
                                    color: ThemeConfig.redColor(context)),
                                textAlign: TextAlign.center,
                              ),
                            ),
                          if (_isAppInstalled)
                            Padding(
                              padding: const EdgeInsets.only(top: 8.0),
                              child: Text(
                                AppManagementStrings.appAlreadyInstalled,
                                style: TextStyle(
                                    fontSize: 16,
                                    color: ThemeConfig.blackColor(context)),
                                textAlign: TextAlign.center,
                              ),
                            ),
                        ],
                      ),
                    ),
                  if (kIsWeb) const PwaStorageAdvancedSettings(),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
