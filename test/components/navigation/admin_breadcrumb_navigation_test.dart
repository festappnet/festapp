import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:fstapp/widgets/dependency_material_bridge.dart';
import 'package:auto_route/auto_route.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:material_ui/material_ui.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fstapp/app_router.gr.dart';
import 'package:fstapp/components/_shared/app_panel_helper.dart';
import 'package:fstapp/components/occasion/occasion_link_model.dart';
import 'package:fstapp/components/occasion/occasion_model.dart';
import 'package:fstapp/components/unit/unit_model.dart';
import 'package:fstapp/components/users/occasion_user_model.dart';
import 'package:fstapp/components/users/user_info_model.dart';
import 'package:fstapp/data_services/rights_service.dart';
import 'package:fstapp/router_service.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:shared_preferences_platform_interface/shared_preferences_async_platform_interface.dart';
import 'package:shared_preferences_platform_interface/in_memory_shared_preferences_async.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class _Strings extends AssetLoader {
  const _Strings();
  @override
  Future<Map<String, dynamic>> load(String path, Locale locale) async => {
    'Common': {
      'eventManagement': 'Správa události',
      'moreOptions': 'Další možnosti',
    },
    'Administration': {
      'viewApp': 'Zobrazit aplikaci',
      'findUnitHint': 'Najít organizaci...',
      'addOrganizationFavorite': 'Přidat mezi oblíbené',
      'removeOrganizationFavorite': 'Odebrat z oblíbených',
    },
  };
}

class _Router extends RootStackRouter {
  CustomRoute page(
    String name,
    String path,
    WidgetBuilder builder, {
    List<AutoRoute>? children,
  }) => CustomRoute(
    page: PageInfo(name, builder: (_) => Builder(builder: builder)),
    path: path,
    children: children,
    transitionsBuilder: TransitionsBuilders.noTransition,
  );
  Widget screen(BuildContext context) => Scaffold(
    appBar: AppPanelHelper.buildAdaptiveAdminAppBar(context),
    body: const Text('SCREEN'),
  );
  @override
  List<AutoRoute> get routes => [
    page(
      'OccasionFixture',
      '/:occasionLink',
      (_) => const AutoRouter(),
      children: [
        page(
          AdminRoute.name,
          'admin',
          (_) => const AutoRouter(),
          children: [
            page('AdminInformationFixture', 'info/information', screen),
          ],
        ),
        page('PublicAppFixture', '', screen),
      ],
    ),
  ];
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final previousPreferences = SharedPreferencesAsyncPlatform.instance;
  final remoteFavorites = <String, Set<int>>{};
  setUpAll(() async {
    SharedPreferences.setMockInitialValues({});
    SharedPreferencesAsyncPlatform.instance =
        InMemorySharedPreferencesAsync.empty();
    await EasyLocalization.ensureInitialized();
    await Supabase.initialize(
      url: 'https://fixture.test',
      publishableKey: 'fixture',
      httpClient: MockClient((request) async {
        expect(request.method, 'POST');
        final args = jsonDecode(request.body) as Map<String, dynamic>;
        final account = args['p_user_id'] as String;
        final favorites = remoteFavorites.putIfAbsent(account, () => {});
        if (request.url.path == '/rest/v1/rpc/set_unit_picker_favorite') {
          final unitId = args['p_unit_id'] as int;
          if (args['p_favorite'] as bool) {
            favorites.add(unitId);
          } else {
            favorites.remove(unitId);
          }
          return http.Response('', 204, request: request);
        }
        expect(request.url.path, '/rest/v1/rpc/get_unit_picker_favorites');
        return http.Response(
          jsonEncode(favorites.toList()),
          200,
          headers: {'content-type': 'application/json'},
          request: request,
        );
      }),
      authOptions: const FlutterAuthClientOptions(detectSessionInUri: false),
    );
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
          isPromoted: false,
        ),
        occasionUser: OccasionUserModel(isEditorView: true),
        capabilities: const {'navigation.administration': true},
      );
      addTearDown(() {
        RightsService.occasionLinkModelNotifier.value = previous;
        RouterService.currentOccasionLink = previousLink;
      });
      final router = _Router();
      await tester.pumpWidget(
        EasyLocalization(
          supportedLocales: const [Locale('cs')],
          path: 'unused',
          assetLoader: const _Strings(),
          child: Builder(
            builder: (context) => MaterialApp.router(
              builder: DependencyMaterialBridge.builder,
              locale: context.locale,
              supportedLocales: context.supportedLocales,
              localizationsDelegates: [
                ...context.localizationDelegates,
                ...GlobalMaterialLocalizations.delegates,
              ],
              routerConfig: router.config(
                deepLinkBuilder: (_) =>
                    const DeepLink.path('/occasion-a/admin/info/information'),
              ),
            ),
          ),
        ),
      );
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
    },
  );

  for (final width in [1200.0, 600.0]) {
    testWidgets(
      'organization favorites preserve picker behavior at width $width',
      (tester) async {
        remoteFavorites.clear();
        tester.view.physicalSize = Size(width, 800);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        final previous = RightsService.occasionLinkModelNotifier.value;
        addTearDown(
          () => RightsService.occasionLinkModelNotifier.value = previous,
        );
        final units = [
          UnitModel(id: 1, title: 'Alfa'),
          UnitModel(id: 2, title: 'Beta'),
          UnitModel(id: 3, title: 'Celesta'),
          UnitModel(id: 4, title: 'Delta'),
          UnitModel(id: 5, title: 'Éta'),
        ];
        void setUnits(int count, {String account = 'first-account'}) {
          RightsService.occasionLinkModelNotifier.value = OccasionLinkModel(
            unit: units.first,
            userInfo: UserInfoModel(
              id: account,
              units: units.take(count).toList(),
            ),
          );
        }

        setUnits(4);
        final router = _Router();
        await tester.pumpWidget(
          EasyLocalization(
            supportedLocales: const [Locale('cs')],
            path: 'unused',
            assetLoader: const _Strings(),
            child: Builder(
              builder: (context) => MaterialApp.router(
                builder: DependencyMaterialBridge.builder,
                locale: context.locale,
                supportedLocales: context.supportedLocales,
                localizationsDelegates: [
                  ...context.localizationDelegates,
                  ...GlobalMaterialLocalizations.delegates,
                ],
                routerConfig: router.config(
                  deepLinkBuilder: (_) => const DeepLink.path('/fixture'),
                ),
              ),
            ),
          ),
        );
        Future<void> openPicker() async {
          await tester.pumpAndSettle();
          await tester.tap(find.byIcon(Icons.unfold_more_rounded));
          await tester.pumpAndSettle();
        }

        Future<void> closePicker() async {
          await tester.tapAt(Offset(width - 5, 790));
          await tester.pumpAndSettle();
        }

        Finder row(String title) => find.widgetWithText(ListTile, title);
        Finder star(String title) =>
            find.descendant(of: row(title), matching: find.byType(IconButton));
        Future<void> toggle(String title) async {
          await tester.tap(star(title));
          await tester.pumpAndSettle();
        }

        double y(String title) => tester.getTopLeft(row(title)).dy;
        final search = find.byType(TextField);

        await openPicker();
        expect(find.byIcon(Icons.star_border), findsNothing);
        await closePicker();

        setUnits(5);
        await openPicker();
        expect(find.byIcon(Icons.star_border), findsNWidgets(5));
        await toggle('Éta');
        await toggle('Delta');
        expect(y('Delta'), lessThan(y('Éta')));
        expect(y('Éta'), lessThan(y('Alfa')));
        expect(y('Alfa'), lessThan(y('Beta')));
        expect(find.byIcon(Icons.check), findsOneWidget);
        expect(router.currentUrl, '/fixture');

        await tester.enterText(search, 'eta');
        await tester.pumpAndSettle();
        expect(y('Éta'), lessThan(y('Beta')));
        expect(row('Delta'), findsNothing);
        await toggle('Éta');
        expect(y('Beta'), lessThan(y('Éta')));
        expect(remoteFavorites['first-account'], {4});
        await closePicker();

        // A different device adds a favorite while the picker is closed.
        remoteFavorites['first-account']!.add(2);
        await openPicker();
        expect(y('Beta'), lessThan(y('Delta')));
        expect(y('Delta'), lessThan(y('Alfa')));
        expect(find.byIcon(Icons.star), findsNWidgets(2));
        await closePicker();

        setUnits(5, account: 'another-account');
        await openPicker();
        expect(find.byIcon(Icons.star), findsNothing);
        expect(y('Alfa'), lessThan(y('Delta')));
        await closePicker();
        await tester.pumpWidget(const SizedBox.shrink());
        router.dispose();
      },
    );
  }
}
