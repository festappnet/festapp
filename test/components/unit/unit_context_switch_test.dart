import 'dart:async';
import 'package:auto_route/auto_route.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fstapp/app_router.gr.dart';
import 'package:fstapp/components/navigation/unit_administration_access.dart';
import 'package:fstapp/components/occasion/occasion_model.dart';
import 'package:fstapp/components/unit/unit_model.dart';
import 'package:fstapp/components/unit/views/unit_admin_page.dart';
import 'package:fstapp/router_service.dart';

class UnitAccess extends ChangeNotifier implements UnitAdministrationAccess {
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
  @override
  bool get canAccess => allowed;
  @override
  Future<void> load(int unitId, {required bool force}) async {
    requests.add(unitId);
    currentUnit = UnitModel(id: unitId);
    notifyListeners();
  }

  @override
  Future<List<OccasionModel>> occasions(int unitId) async => [];
}

void main() {
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
    await tester.pumpWidget(MaterialApp.router(
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
