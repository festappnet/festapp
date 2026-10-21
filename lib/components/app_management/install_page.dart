import 'package:auto_route/auto_route.dart';
import 'package:collection/collection.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:fstapp/app_config.dart';
import 'package:fstapp/components/_shared/common_strings.dart';
import 'package:fstapp/components/app_management/app_management_strings.dart';
import 'package:fstapp/components/organization/organization_model.dart';
import 'package:fstapp/components/organization/db_organizations.dart';
import 'package:fstapp/router_service.dart';
import 'package:fstapp/services/js/js_interop.dart';
import 'package:fstapp/services/launch_url_service.dart';
import 'package:fstapp/services/platform_helper.dart';
import 'package:fstapp/services/app_logger.dart';
import 'package:fstapp/services/toast_helper.dart';
import 'package:fstapp/styles/styles_config.dart';
import 'package:fstapp/theme_config.dart';
import 'package:fstapp/widgets/buttons_helper.dart';
import 'package:pwa_install/pwa_install.dart';

@RoutePage()
class InstallPage extends StatefulWidget {
  static final JSInterop jsInterop = JSInterop();
  static const ROUTE = "install";
  const InstallPage({super.key});

  @override
  _InstallPageState createState() => _InstallPageState();
}

class _InstallPageState extends State<InstallPage> {
  bool _isAppInstalled = false;
  bool _isPromptEnabled = false;
  bool _installFailed = false;
  bool _isLoading = true;
  bool _didRunInitialLoad = false;
  String platform = "";
  List<PlatformModel> _platforms = [];
  final TextEditingController _urlController = TextEditingController();
  final List<ExpansibleController> _controllers = [
    ExpansibleController(),
    ExpansibleController(),
    ExpansibleController(),
  ];

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (!_didRunInitialLoad) {
      _didRunInitialLoad = true;
      _loadInitialData();
    }
  }

  Future<void> _loadInitialData() async {
    platform = InstallPage.jsInterop.getOSInsideWeb();
    try {
      final platforms = await DbOrganizations.getAvailablePlatforms(
          organizationId: AppConfig.organization);
      if (mounted) {
        setState(() {
          _platforms = platforms;
        });
      }
    } catch (e) {
      AppLogger.error("Failed to load platforms: $e");
      if (mounted) {
        ToastHelper.Show(context, AppManagementStrings.installOptionsLoadFailed,
            severity: ToastSeverity.NotOk);
      }
    }
    await _loadPwaSettings();
    if (mounted) {
      setState(() {
        _isLoading = false;
      });
    }
  }

  Future<void> _loadPwaSettings() async {
    bool isAppInstalled = PlatformHelper.isPwaInstalledOrNative();
    setState(() {
      _isAppInstalled = isAppInstalled;
      _isPromptEnabled = PWAInstall().installPromptEnabled;
    });
  }

  Future<void> handleInstallButtonPress() async {
    try {
      PWAInstall().promptInstall_();
    } catch (e) {
      final webLink =
          _platforms.firstWhereOrNull((p) => p.platform == 'web')?.link ??
              RouterService.getCurrentUri().toString();
      setState(() {
        _installFailed = true;
        _urlController.text = webLink;
        _urlController.selection = TextSelection(
            baseOffset: 0, extentOffset: _urlController.text.length);
      });
    }
    await _loadPwaSettings();
  }

  bool get _canInstallPWA =>
      !_isAppInstalled && !_installFailed && _isPromptEnabled;

  void _handleExpansion(int index) {
    setState(() {
      for (int i = 0; i < _controllers.length; i++) {
        if (i == index) {
          _controllers[i].expand();
        } else {
          _controllers[i].collapse();
        }
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final appleLink =
        _platforms.firstWhereOrNull((p) => p.platform == 'ios')?.link;
    final androidLink =
        _platforms.firstWhereOrNull((p) => p.platform == 'droid')?.link;

    return Scaffold(
      appBar: AppBar(
        title: Text(AppManagementStrings.installApp),
        leading: BackButton(
          onPressed: () => RouterService.goBackOrInitial(context),
        ),
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : Align(
              alignment: Alignment.topCenter,
              child: Padding(
                padding: const EdgeInsets.all(32.0),
                child: ConstrainedBox(
                  constraints:
                      BoxConstraints(maxWidth: StylesConfig.appMaxWidth),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: [
                      // App Icon and Explanation
                      Center(
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          mainAxisSize: MainAxisSize.max,
                          children: [
                            Container(
                              width: 64,
                              height: 64,
                              decoration: BoxDecoration(
                                borderRadius: BorderRadius.circular(12.0),
                                image: const DecorationImage(
                                  image:
                                      AssetImage('assets/icons/fstappicon.png'),
                                  fit: BoxFit.cover,
                                ),
                              ),
                            ),
                            const SizedBox(width: 22),
                            Expanded(
                              child: Text(
                                AppManagementStrings.installBenefits(
                                    title: AppConfig.appName),
                                style: TextStyle(
                                  fontSize: 16,
                                  color: ThemeConfig.blackColor(context),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 48),
                      // Install Sections
                      if (appleLink != null && appleLink.isNotEmpty)
                        buildInstallSection(
                          context,
                          AppManagementStrings.installForApple,
                          Icons.apple,
                          appleLink,
                          0,
                        ),
                      buildInstallSection(
                        context,
                        AppManagementStrings.installForAndroid,
                        Icons.android,
                        androidLink,
                        1,
                        notice: androidLink == null || androidLink.isEmpty
                            ? AppManagementStrings.androidInstallHint
                            : null,
                      ),
                      buildInstallSection(
                        context,
                        AppManagementStrings.installForPcMac,
                        Icons.desktop_windows,
                        null,
                        2,
                      ),
                    ],
                  ),
                ),
              ),
            ),
    );
  }

  Widget buildInstallSection(
    BuildContext context,
    String title,
    IconData icon,
    String? link,
    int index, {
    String? notice,
  }) {
    final bool hasNativeLink = link != null && link.isNotEmpty;
    return ExpansionTile(
      controller: _controllers[index],
      initiallyExpanded: platform == "ios" && index == 0 ||
          platform == "android" && index == 1 ||
          platform == "web" && index == 2,
      title: Row(
        children: [
          Icon(icon, size: 24),
          const SizedBox(width: 10),
          Text(title, style: const TextStyle(fontWeight: FontWeight.bold)),
        ],
      ),
      onExpansionChanged: (expanded) {
        if (expanded) {
          _handleExpansion(index);
        }
      },
      children: [
        if (notice != null) ...[
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16.0),
            child: Text(
              notice,
              style: TextStyle(
                  color: ThemeConfig.blackColor(context).withOpacity(0.8)),
            ),
          ),
          const SizedBox(height: 10),
        ],
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16.0),
          child: Column(
            children: [
              ButtonsHelper.bigButton(
                context: context,
                label: hasNativeLink
                    ? AppManagementStrings.downloadApp
                    : AppManagementStrings.installNow,
                onPressed: hasNativeLink
                    ? () => LaunchUrlService.openExternalUrl(link)
                    : _canInstallPWA
                        ? handleInstallButtonPress
                        : null,
                color: (hasNativeLink || _canInstallPWA)
                    ? ThemeConfig.seed1
                    : Colors.grey,
                textColor: Colors.white,
              ),
              if (!hasNativeLink) ...[
                if (_isAppInstalled)
                  Padding(
                    padding: const EdgeInsets.only(top: 8.0),
                    child: Text(
                      AppManagementStrings.appAlreadyInstalled,
                      style: TextStyle(fontSize: 16, color: ThemeConfig.seed1),
                      textAlign: TextAlign.center,
                    ),
                  ),
                if (_installFailed)
                  Padding(
                    padding: const EdgeInsets.only(top: 8.0),
                    child: Column(
                      children: [
                        Text(
                          AppManagementStrings.installFailedHint,
                          style: const TextStyle(color: Colors.red),
                          textAlign: TextAlign.center,
                        ),
                        const SizedBox(height: 8.0),
                        Row(
                          children: [
                            Expanded(
                              child: TextFormField(
                                controller: _urlController,
                                readOnly: true,
                              ),
                            ),
                            const SizedBox(width: 8.0),
                            TextButton.icon(
                              onPressed: () {
                                Clipboard.setData(
                                    ClipboardData(text: _urlController.text));
                                ToastHelper.Show(
                                    context, CommonStrings.copiedToClipboard);
                              },
                              icon: const Icon(Icons.copy),
                              label: Text(AppManagementStrings.copyLink),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                if (!_isAppInstalled && !_installFailed && !_isPromptEnabled)
                  Padding(
                    padding: const EdgeInsets.only(top: 8.0),
                    child: Text(
                      AppManagementStrings.pwaPromptNotSupported,
                      style: const TextStyle(color: Colors.red),
                      textAlign: TextAlign.center,
                    ),
                  ),
              ]
            ],
          ),
        ),
        const SizedBox(height: 16),
      ],
    );
  }
}
