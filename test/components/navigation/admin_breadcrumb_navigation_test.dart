import 'package:auto_route/auto_route.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fstapp/app_router.gr.dart';
import 'package:fstapp/components/_shared/app_panel_helper.dart';
import 'package:fstapp/components/occasion/occasion_link_model.dart';
import 'package:fstapp/components/occasion/occasion_model.dart';
import 'package:fstapp/components/unit/unit_model.dart';
import 'package:fstapp/components/users/occasion_user_model.dart';
import 'package:fstapp/data_services/rights_service.dart';
import 'package:fstapp/router_service.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:shared_preferences_platform_interface/shared_preferences_async_platform_interface.dart';
import 'package:shared_preferences_platform_interface/types.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

final class _Preferences extends SharedPreferencesAsyncPlatform {
  @override
  Future<String?> getString(
          String key, SharedPreferencesOptions options) async =>
      null;
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _Strings extends AssetLoader {
  const _Strings();
  @override
  Future<Map<String, dynamic>> load(String path, Locale locale) async => {
        'Common': {
          'eventManagement': 'Správa události',
          'moreOptions': 'Další možnosti'
        },
        'Administration': {'viewApp': 'Zobrazit aplikaci'},
      };
}

class _Router extends RootStackRouter {
  CustomRoute page(String name, String path, WidgetBuilder builder,
          {List<AutoRoute>? children}) =>
      CustomRoute(
        page: PageInfo(name, builder: (_) => Builder(builder: builder)),
        path: path,
        children: children,
        transitionsBuilder: TransitionsBuilders.noTransition,
      );
  Widget screen(BuildContext context) => Scaffold(
        appBar: AppPanelHelper.buildDesktopAdminAppBar(context, null, null),
        body: const Text('SCREEN'),
      );
  @override
  List<AutoRoute> get routes => [
        page('OccasionFixture', '/:occasionLink', (_) => const AutoRouter(),
            children: [
              page(AdminRoute.name, 'admin', (_) => const AutoRouter(),
                  children: [
                    page('AdminInformationFixture', 'info/information', screen),
                  ]),
              page('PublicAppFixture', '', screen),
            ])
      ];
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final previousPreferences = SharedPreferencesAsyncPlatform.instance;
  setUpAll(() async {
    SharedPreferences.setMockInitialValues({});
    SharedPreferencesAsyncPlatform.instance = _Preferences();
    await EasyLocalization.ensureInitialized();
    await Supabase.initialize(
        url: 'https://fixture.test',
        publishableKey: 'fixture',
        authOptions: const FlutterAuthClientOptions(detectSessionInUri: false));
  });
  tearDownAll(() async {
    SharedPreferencesAsyncPlatform.instance = previousPreferences;
    await Supabase.instance.dispose();
  });
  testWidgets(
      'nested administration shows its action and opens the app from its menu',
      (tester) async {
    tester.view.physicalSize = const Size(1600, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final previous = RightsService.occasionLinkModelNotifier.value;
    final previousLink = RouterService.currentOccasionLink;
    RouterService.currentOccasionLink = 'occasion-a';
    RightsService.occasionLinkModelNotifier.value = OccasionLinkModel(
      unit: UnitModel(id: 999, title: 'Festival'),
      occasion: OccasionModel(
          id: 12,
          title: 'WE 2026',
          link: 'occasion-a',
          isOpen: true,
          isHidden: false,
          isPromoted: false),
      occasionUser: OccasionUserModel(isEditorView: true),
    );
    addTearDown(() {
      RightsService.occasionLinkModelNotifier.value = previous;
      RouterService.currentOccasionLink = previousLink;
    });
    final router = _Router();
    await tester.pumpWidget(EasyLocalization(
      supportedLocales: const [Locale('cs')],
      path: 'unused',
      assetLoader: const _Strings(),
      child: Builder(
          builder: (context) => MaterialApp.router(
                locale: context.locale,
                supportedLocales: context.supportedLocales,
                localizationsDelegates: context.localizationDelegates,
                routerConfig: router.config(
                    deepLinkBuilder: (_) => const DeepLink.path(
                        '/occasion-a/admin/info/information')),
              )),
    ));
    await tester.pumpAndSettle();
    expect(find.text('Správa události'), findsOneWidget);
    expect(find.text('Zobrazit aplikaci'), findsNothing);
    await tester.tap(find.byIcon(Icons.arrow_drop_down));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Zobrazit aplikaci'));
    await tester.pumpAndSettle();
    expect(router.currentUrl, '/occasion-a');
    expect(find.text('Zobrazit aplikaci'), findsOneWidget);
    // The title is a direct link, and the menu does not leave a click barrier.
    await tester.tap(find.text('Zobrazit aplikaci'));
    await tester.pumpAndSettle();
    expect(find.byType(PopupMenuItem), findsNothing);
    await tester.pumpWidget(const SizedBox.shrink());
    router.dispose();
  });
}
