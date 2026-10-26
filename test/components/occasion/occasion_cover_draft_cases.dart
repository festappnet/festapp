import 'package:fstapp/widgets/dependency_material_bridge.dart';
import 'package:timezone/timezone.dart' as fixtureTimezone;
import 'package:fstapp/data_services/authorization_capabilities.dart';
import '../../support/fixtures/widget_environment_fixture.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:fstapp/app_router.dart';
import 'dart:convert';
import 'dart:io';
import 'package:auto_route/auto_route.dart';
import 'package:material_ui/material_ui.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fstapp/components/_shared/common_strings.dart';
import 'package:fstapp/components/_shared/editor_action_bar.dart';
import 'package:fstapp/components/images/image_area.dart';
import 'package:fstapp/components/occasion/occasion_link_model.dart';
import 'package:fstapp/components/occasion_settings/occasion_settings_tab.dart';
import 'package:fstapp/components/users/occasion_user_model.dart';
import 'package:fstapp/data_services/rights_service.dart';
import 'package:fstapp/components/occasion/occasion_model.dart';
import 'package:festapp_core/time.dart' as tz;

late WidgetEnvironmentFixture _environment;

class _Router extends RootStackRouter {
  @override
  List<AutoRoute> get routes => [
        AutoRoute(
            path: '/:${AppRouter.linkFormatted}/settings',
            page: PageInfo('Settings',
                builder: (_) => OccasionSettingsTab(
                    loadOccasion: (_) async => OccasionModel(
                            id: 59,
                            link: 'example',
                            title: 'Example',
                            isOpen: true,
                            isHidden: false,
                            isPromoted: false,
                            startTime: DateTime(2027, 1, 1),
                            endTime: DateTime(2027, 1, 2),
                            data: {
                              'timezone': 'Europe/Prague',
                              'image':
                                  'https://img.festapp.net/images/59/original.jpg'
                            },
                            features: []))))
      ];
}

void main() {
  WidgetEnvironmentFixture.register();
  const cover = 'https://img.festapp.net/images/59/original.jpg';
  setUpAll(() async {
    SharedPreferences.setMockInitialValues({});
    await EasyLocalization.ensureInitialized();
    await initializeDateFormatting('cs');
    if (!fixtureTimezone.timeZoneDatabase.isInitialized) {
      tz.OccasionTimeContext.initializeTimeZones();
    }
    final previousZone = fixtureTimezone.local;
    addTearDown(() => fixtureTimezone.setLocalLocation(previousZone));
    _environment = WidgetEnvironmentFixture(
        locale: const Locale('cs'),
        translations:
            jsonDecode(File('assets/translations/cs.json').readAsStringSync())
                as Map<String, dynamic>);
  });
  testWidgetsWithEnvironment(() => _environment,
      'cover-only removal is an unsaved draft; discard restores its original without writes',
      (tester) async {
    tester.view.physicalSize = const Size(1200, 1800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final previousRights = RightsService.occasionLinkModelNotifier.value;
    RightsService.occasionLinkModelNotifier.value = OccasionLinkModel(
        capabilities: {AuthorizationCapabilities.occasionsWrite: true},
        unitUser: OccasionUserModel(isEditor: true));
    addTearDown(
        () => RightsService.occasionLinkModelNotifier.value = previousRights);
    final router = _Router();
    await _environment.pumpWidget(
        tester,
        EasyLocalization(
            supportedLocales: const [Locale('cs')],
            startLocale: const Locale('cs'),
            path: 'assets/translations',
            child: MaterialApp.router(builder: DependencyMaterialBridge.builder,
                routerConfig: router.config(
                    deepLinkBuilder: (_) =>
                        const DeepLink.path('/example/settings')))));
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));
    expect(
        tester.widget<EditorActionBar>(find.byType(EditorActionBar)).hasChanges,
        isFalse);
    tester.widget<ImageArea>(find.byType(ImageArea)).onRemove();
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));
    await tester.tap(find.widgetWithText(ElevatedButton, CommonStrings.ok));
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));
    expect(tester.widget<ImageArea>(find.byType(ImageArea)).imageUrl, isNull);
    expect(
        tester.widget<EditorActionBar>(find.byType(EditorActionBar)).hasChanges,
        isTrue);
    await tester
        .widget<EditorActionBar>(find.byType(EditorActionBar))
        .onDiscard();
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));
    expect(tester.widget<ImageArea>(find.byType(ImageArea)).imageUrl, cover);
    expect(
        tester.widget<EditorActionBar>(find.byType(EditorActionBar)).hasChanges,
        isFalse);
  });
}
