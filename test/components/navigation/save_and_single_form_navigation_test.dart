import 'dart:convert';
import 'dart:io';
import 'package:easy_localization/src/localization.dart';
import 'package:easy_localization/src/translations.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fstapp/components/forms/models/form_model.dart';
import 'package:fstapp/components/forms/views/forms_tab.dart';
import 'package:fstapp/components/occasion_settings/occasion_save_state.dart';
import '../../support/navigation_fixture.dart';
import 'routed_tab_navigation_test.dart' show mount;

void main() {
  setUp(() => Localization.load(const Locale('cs'),
      translations: Translations(
          jsonDecode(File('assets/translations/cs.json').readAsStringSync()))));
  testWidgets('saving keeps the selected section and all query values',
      (tester) async {
    final router = FixtureRouter(Access());
    const path =
        '/occasion-a/reservations/forms/second/responses?day=2026-10-03&preview-day=2026-10-10';
    await mount(tester, router, path);
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

  for (final count in [0, 1, 2]) {
    testWidgets('$count forms choose detail only for a single form',
        (tester) async {
      final router = FixtureRouter(Access())
        ..formsListBuilder = (_) => FormsListView(
              loadForms: (_) async => List.generate(
                  count,
                  (i) =>
                      FormModel(id: i + 1, link: 'form-$i', title: 'Form $i')),
            );
      await mount(tester, router, '/occasion-a/reservations/forms');
      expect(
          router.currentUrl,
          count == 1
              ? '/occasion-a/reservations/forms/form-0/editor'
              : '/occasion-a/reservations/forms');
    });
  }
  testWidgets('explicit list remains available with one form', (tester) async {
    final router = FixtureRouter(Access())
      ..formsListBuilder = (_) => FormsListView(
            loadForms: (_) async =>
                [FormModel(id: 1, link: 'single', title: 'Single')],
          );
    await mount(tester, router, '/occasion-a/reservations/forms?list=true');
    expect(router.currentUrl, '/occasion-a/reservations/forms?list=true');
    expect(find.text('Single'), findsOneWidget);
  });
}
