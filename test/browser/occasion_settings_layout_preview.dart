// Run with fvm flutter run -d web-server --target
// test/browser/occasion_settings_layout_preview.dart --web-port 59273.
// This entrypoint installs no production authentication or database transport.
import 'package:easy_localization/easy_localization.dart';
import 'package:auto_route/auto_route.dart';
import 'package:material_ui/material_ui.dart';
import 'package:fstapp/services/time_helper.dart';
import 'package:fstapp/services/web_bootstrap_bridge.dart';
import 'package:fstapp/theme_config.dart';
import 'package:fstapp/widgets/dependency_material_bridge.dart';

import '../support/fixtures/occasion_settings_fixture.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized().ensureSemantics();
  await EasyLocalization.ensureInitialized();
  await TimeHelper.initializeTimeZone();
  final fixture = OccasionSettingsFixture()..installRights();
  final router = OccasionSettingsFixtureRouter(fixture);
  runApp(
    EasyLocalization(
      supportedLocales: const [Locale('cs')],
      startLocale: const Locale('cs'),
      saveLocale: false,
      path: 'assets/translations',
      child: Builder(
        builder: (context) => MaterialApp.router(
          builder: DependencyMaterialBridge.builder,
          theme: ThemeConfig.theme(),
          themeMode: ThemeMode.light,
          locale: context.locale,
          supportedLocales: context.supportedLocales,
          localizationsDelegates: [
            ...context.localizationDelegates,
            ...GlobalMaterialLocalizations.delegates,
          ],
          routerConfig: router.config(
            deepLinkBuilder: (_) => DeepLink.path('/ples-u-lipy/settings'),
          ),
        ),
      ),
    ),
  );
  WidgetsBinding.instance.addPostFrameCallback(
    (_) => WebBootstrapBridge.markAppReady(),
  );
}
