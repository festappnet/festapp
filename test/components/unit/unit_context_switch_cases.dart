import 'package:fstapp/widgets/dependency_material_bridge.dart';
import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:fstapp/components/unit/db_units.dart';
import 'package:fstapp/components/unit/views/occasions_screen.dart';
import 'package:fstapp/components/occasion/demo/demo_catalog.dart';
import 'package:fstapp/components/occasion/demo/demo_occasions_section.dart';
import 'package:fstapp/components/unit/unit_occasion_dashboard.dart';
import '../../support/fixtures/localization_log_fixture.dart';
import 'dart:async';
import 'package:auto_route/auto_route.dart';
import 'package:material_ui/material_ui.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fstapp/app_router.gr.dart';
import 'package:fstapp/components/navigation/unit_administration_access.dart';
import 'package:fstapp/components/occasion/occasion_model.dart';
import 'package:fstapp/components/unit/unit_model.dart';
import 'package:fstapp/components/unit/views/unit_admin_page.dart';
import 'package:fstapp/router_service.dart';
import 'package:fstapp/components/navigation/administration_loading_shell.dart';

class UnitAccess extends ChangeNotifier implements UnitAdministrationAccess {
  @override
  UnitOccasionDashboard? get dashboard => null;
  final requests = <int>[];
  @override
  UnitModel? currentUnit;
  @override
  Listenable get changes => this;
  @override
  bool get isSignedIn => true;
  @override
  bool get hasOccasion => false;
  bool allowed = true;
  bool unresolved = false;
  Future<void> Function(int)? beforeLoad;
  @override
  bool get canAccess => allowed;
  @override
  Future<void> load(int unitId, {required bool force}) async {
    requests.add(unitId);
    await beforeLoad?.call(unitId);
    if (unresolved) {
      await Future<void>.delayed(const Duration(milliseconds: 10));
      currentUnit = null;
      notifyListeners();
      throw StateError('Denied unit without metadata');
    }
    currentUnit = UnitModel(id: unitId);
    notifyListeners();
  }

  @override
  Future<List<OccasionModel>> occasions(int unitId) async => [];
}

void main() {
  // This suite intentionally uses untranslated key fallback (no catalog).
  setUp(() {
    final logs = LocalizationLogFixture.install(expectedMissingCatalog: true);
    addTearDown(logs.dispose);
  });
  Map<String, dynamic> emptyDashboard(int unit) => {
        'unit_id': unit,
        'occasions': [],
        'drafts': [],
        'app_landing': {'enabled': false, 'can_manage': false},
        'demo_catalog': {'items': [], 'hasOwnWork': false},
      };
  test('whole dashboard refresh performs exactly one RPC', () async {
    final requests = <http.Request>[];
    final transport = MockClient((request) async {
      requests.add(request);
      expect(request.url.path, '/rest/v1/rpc/get_unit_edit_data');
      expect(jsonDecode(request.body), {'p_unit_id': 7});
      return http.Response(jsonEncode(emptyDashboard(7)), 200,
          request: request, headers: {'content-type': 'application/json'});
    });
    final client = SupabaseClient('https://fixture.invalid', 'public-test-key',
        httpClient: transport);
    addTearDown(client.dispose);
    addTearDown(transport.close);
    final result = await DbUnits.getOccasionDashboard(7, client: client);
    expect(result.unitId, 7);
    expect(result.occasions, isEmpty);
    expect(result.drafts, isEmpty);
    expect(result.landing!.enabled, isFalse);
    expect(result.demos.items, isEmpty);
    expect(requests, hasLength(1));
  });
  testWidgets(
      'context dashboard renders without an initialized SDK or follow-up reads',
      (tester) async {
    await tester.pumpWidget(MaterialApp(builder: DependencyMaterialBridge.builder,
        home: OccasionsScreen(
            unit: UnitModel(id: 7),
            initialDashboard:
                UnitOccasionDashboard.fromJson(emptyDashboard(7)))));
    await tester.pumpAndSettle();
    expect(find.byType(RefreshIndicator), findsOneWidget);
    expect(tester.takeException(), isNull);
    expect(find.text('Common.retry'), findsNothing);
  });
  testWidgets('provided demo catalogue performs no independent load',
      (tester) async {
    var loads = 0;
    await tester.pumpWidget(MaterialApp(builder: DependencyMaterialBridge.builder,
        home: Scaffold(
            body: DemoOccasionsSection(
                initialCatalog: const DemoCatalog(hasOwnWork: false, items: []),
                load: () async {
                  loads++;
                  return const DemoCatalog(hasOwnWork: false, items: []);
                }))));
    await tester.pumpAndSettle();
    expect(loads, 0);
    expect(tester.takeException(), isNull);
  });
  testWidgets('unit switch uses navigation chrome while destination is pending',
      (tester) async {
    final pending = Completer<void>();
    final access = UnitAccess()
      ..beforeLoad = (id) => id == 2 ? pending.future : Future.value();
    final router = RootStackRouter.build(routes: [
      AutoRoute(
          page: PageInfo(UnitAdminRoute.name,
              builder: (data) =>
                  UnitAdminPage(id: data.params.getInt('id'), access: access)),
          path: '/unit/:id/edit',
          usesPathAsKey: true,
          children: [
            AutoRoute(
                page: PageInfo('UnitContent',
                    builder: (_) => Builder(
                        builder: (context) => Text(
                            'UNIT ${UnitAdministrationScope.of(context).unit.id}'))),
                path: '',
                initial: true)
          ])
    ]);
    await tester.pumpWidget(MaterialApp.router(builder: DependencyMaterialBridge.builder,
        routerConfig: router.config(
            deepLinkBuilder: (_) => DeepLink.path('/unit/1/edit'))));
    await tester.pumpAndSettle();
    unawaited(RouterService.navigateToUnitAdmin(
        tester.element(find.text('UNIT 1')), UnitModel(id: 2)));
    for (var i = 0; i < 10; i++) {
      await tester.pump(const Duration(milliseconds: 50));
    }
    expect(find.byType(AdministrationLoadingShell), findsOneWidget);
    expect(tester.getRect(find.byType(AdministrationLoadingShell)),
        const Rect.fromLTWH(0, 0, 800, 600));
    expect(find.text('UNIT 2'), findsNothing);
    pending.complete();
    await tester.pump(const Duration(milliseconds: 16));
    expect(
        find.byType(AdministrationLoadingShell).hitTestable(), findsOneWidget,
        reason:
            'The initial nested router frame must retain navigation chrome');
    await tester.pumpAndSettle();
    expect(find.text('UNIT 2'), findsOneWidget);
    expect(access.requests, [1, 2]);
  });

  testWidgets('failed unit context does not repeatedly reload', (tester) async {
    final access = UnitAccess()..unresolved = true;
    final router = RootStackRouter.build(routes: [
      AutoRoute(
          page: PageInfo(UnitAdminRoute.name,
              builder: (_) => UnitAdminPage(id: 1, access: access)),
          path: '/unit/1/edit',
          usesPathAsKey: true)
    ]);
    await tester.pumpWidget(MaterialApp.router(builder: DependencyMaterialBridge.builder,
        routerConfig: router.config(
            deepLinkBuilder: (_) => DeepLink.path('/unit/1/edit'))));
    for (var i = 0; i < 30; i++) {
      await tester.pump(const Duration(milliseconds: 50));
    }
    expect(access.requests, [1]);
    expect(find.byType(CircularProgressIndicator), findsNothing);
    expect(find.byType(TextButton), findsOneWidget);
    expect(tester.binding.hasScheduledFrame, isFalse);
  });

  testWidgets('breadcrumb unit switch and Back load only the visible unit',
      (tester) async {
    final access = UnitAccess();
    late BuildContext selectedContext;
    final router = RootStackRouter.build(routes: [
      AutoRoute(
        page: PageInfo(UnitAdminRoute.name,
            builder: (data) =>
                UnitAdminPage(id: data.params.getInt('id'), access: access)),
        path: '/unit/:id/edit',
        usesPathAsKey: true,
        children: [
          AutoRoute(
              page: PageInfo('UnitContent',
                  builder: (data) => Builder(builder: (context) {
                        selectedContext = context;
                        return Text(
                            'UNIT ${UnitAdministrationScope.of(context).unit.id}');
                      })),
              path: '',
              initial: true)
        ],
      ),
    ]);
    await tester.pumpWidget(MaterialApp.router(builder: DependencyMaterialBridge.builder,
        routerConfig: router.config(
            deepLinkBuilder: (_) => DeepLink.path('/unit/1/edit'))));
    await tester.pumpAndSettle();
    expect(access.requests, [1]);
    unawaited(
        RouterService.navigateToUnitAdmin(selectedContext, UnitModel(id: 2)));
    for (var i = 0; i < 12; i++) {
      await tester.pump(const Duration(milliseconds: 50));
    }
    expect(access.requests, [1, 2]);
    expect(router.currentUrl, '/unit/2/edit');
    expect(find.text('UNIT 2'), findsOneWidget);
    await router.maybePop();
    await tester.pumpAndSettle();
    expect(access.requests, [1, 2, 1]);
    expect(find.text('UNIT 1'), findsOneWidget);
    access.allowed = false;
    access.notifyListeners();
    await tester.pumpAndSettle();
    expect(find.text('UNIT 1'), findsNothing);
    access.allowed = true;
    access.notifyListeners();
    await tester.pumpAndSettle();
    expect(find.text('UNIT 1'), findsOneWidget);
    expect(access.requests, [1, 2, 1]);
    unawaited(
        RouterService.navigateToUnitAdmin(selectedContext, UnitModel(id: 2)));
    await tester.pumpAndSettle();
    const target = '/unit/1/edit';
    await router.delegate().setNewRoutePath(UrlState(Uri.parse(target),
        router.matcher.match(target, includePrefixMatches: false)!));
    await tester.pumpAndSettle();
    expect(access.requests, [1, 2, 1, 2, 1]);
    expect(find.text('UNIT 1'), findsOneWidget);
  });
}
