import '../../support/fixtures/widget_environment_fixture.dart';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:auto_route/auto_route.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fstapp/components/forms/models/form_editor_draft.dart';
import 'package:fstapp/components/forms/views/forms_tab.dart';
import 'package:fstapp/app_router.gr.dart';
import 'package:fstapp/components/_shared/common_strings.dart';
import 'package:fstapp/components/occasion_settings/occasion_save_state.dart';
import '../../support/navigation_fixture.dart';
import 'routed_tab_navigation_cases.dart' show mount;

late WidgetEnvironmentFixture _environment;

void main() {
  WidgetEnvironmentFixture.register();
  setUp(() => _environment = WidgetEnvironmentFixture(
      locale: const Locale('cs'),
      translations:
          jsonDecode(File('assets/translations/cs.json').readAsStringSync())));
  testWidgetsWithEnvironment(() => _environment,
      'saving keeps the selected section and all query values', (tester) async {
    final router = FixtureRouter(Access());
    const path =
        '/occasion-a/reservations/forms/second/responses?day=2026-10-03&preview-day=2026-10-10';
    await mount(tester, router, path, environment: _environment);
    await refreshSavedOccasion(
        router: router,
        previousLink: 'occasion-a',
        savedLink: 'occasion-a',
        refresh: (_) async {});
    await tester.pumpAndSettle();
    expect(router.currentUrl, path);
    expect(find.text('RESPONSES CONTENT'), findsOneWidget);
    await refreshSavedOccasion(
        router: router,
        previousLink: 'occasion-a',
        savedLink: 'renamed',
        refresh: (_) async {});
    await tester.pumpAndSettle();
    expect(router.currentUrl, path.replaceFirst('occasion-a', 'renamed'));
    expect(find.text('RESPONSES CONTENT'), findsOneWidget);
  });

  testWidgetsWithEnvironment(() => _environment,
      'automatic single-form entry has no nested page transition',
      (tester) async {
    final router = FixtureRouter(Access())
      ..formsListBuilder = (_) => FormsListView(
          loadForms: (_) async => [
                FormEditorDraft(id: 1, link: 'single', title: 'Single')
                    .toBundle()
              ]);
    await _environment.pumpWidget(
        tester,
        MaterialApp.router(
            routerConfig: router.config(
                deepLinkBuilder: (_) =>
                    const DeepLink.path('/occasion-a/reservations/forms'))));
    for (var i = 0; i < 30; i++) {
      await tester.pump(const Duration(milliseconds: 1));
      if (find.byKey(const Key('draft-field')).evaluate().isNotEmpty) break;
    }
    await tester.pump();
    final detailRoute =
        ModalRoute.of(tester.element(find.byKey(const Key('draft-field'))))!;
    expect(detailRoute.animation!.isCompleted, isTrue,
        reason: 'Automatic selection must not slide in a second nested page');
    await tester.pumpAndSettle();
    await tester.tap(find.text('Responses'));
    await tester.pump(const Duration(milliseconds: 30));
    final bar = tester.widget<TabBar>(find.ancestor(
        of: find.text('Responses'), matching: find.byType(TabBar)));
    expect(bar.controller!.indexIsChanging, isTrue,
        reason: 'User-requested subtab switches retain their normal animation');
    await tester.pumpAndSettle();
    expect(
        router.currentUrl, '/occasion-a/reservations/forms/single/responses');
  });

  for (final count in [0, 1, 2]) {
    testWidgetsWithEnvironment(
        () => _environment, '$count forms choose detail only for a single form',
        (tester) async {
      final router = FixtureRouter(Access())
        ..formsListBuilder = (_) => FormsListView(
              loadForms: (_) async => List.generate(
                  count,
                  (i) => FormEditorDraft(
                          id: i + 1, link: 'form-$i', title: 'Form $i')
                      .toBundle()),
            );
      await mount(tester, router, '/occasion-a/reservations/forms',
          environment: _environment);
      expect(
          router.currentUrl,
          count == 1
              ? '/occasion-a/reservations/forms/form-0/editor'
              : '/occasion-a/reservations/forms');
    });
  }
  testWidgetsWithEnvironment(
      () => _environment, 'explicit list remains available with one form',
      (tester) async {
    final router = FixtureRouter(Access())
      ..formsListBuilder = (_) => FormsListView(
            loadForms: (_) async => [
              FormEditorDraft(id: 1, link: 'single', title: 'Single').toBundle()
            ],
          );
    await mount(tester, router, '/occasion-a/reservations/forms?list=true',
        environment: _environment);
    expect(router.currentUrl, '/occasion-a/reservations/forms?list=true');
    expect(find.text('Single'), findsOneWidget);
  });
  testWidgetsWithEnvironment(() => _environment,
      'return from automatic detail renders the explicit forms list',
      (tester) async {
    final router = FixtureRouter(Access())
      ..formsListBuilder = (_) => FormsListView(
            loadForms: (_) async => [
              FormEditorDraft(id: 1, link: 'single', title: 'Single').toBundle()
            ],
          );
    await mount(tester, router, '/occasion-a/reservations/forms',
        environment: _environment);
    final detailContext = tester.element(find.byKey(const Key('draft-field')));
    await detailContext.router.replaceAll([
      const PageRouteInfo(FormsListRoute.name, rawQueryParams: {'list': true}),
    ]);
    for (var i = 0; i < 20; i++) {
      await tester.pump(const Duration(milliseconds: 50));
    }
    expect(router.currentUrl, '/occasion-a/reservations/forms?list=true');
    expect(find.byType(CircularProgressIndicator), findsNothing);
    expect(find.text('Single'), findsOneWidget);
  });
  testWidgetsWithEnvironment(
      () => _environment, 'failed list request stops loading and can retry',
      (tester) async {
    var fail = true;
    final router = FixtureRouter(Access())
      ..formsListBuilder = (_) => FormsListView(loadForms: (_) async {
            if (fail) throw StateError('offline');
            return [
              FormEditorDraft(id: 1, link: 'single', title: 'Single').toBundle()
            ];
          });
    await _environment.pumpWidget(
        tester,
        MaterialApp.router(
            routerConfig: router.config(
                deepLinkBuilder: (_) => const DeepLink.path(
                    '/occasion-a/reservations/forms?list=true'))));
    for (var i = 0; i < 20; i++) {
      await tester.pump(const Duration(milliseconds: 50));
    }
    tester.takeException();
    expect(find.byType(CircularProgressIndicator), findsNothing);
    fail = false;
    await tester.tap(find.text(CommonStrings.retry));
    await tester.pumpAndSettle();
    expect(find.text('Single'), findsOneWidget);
  });
}
