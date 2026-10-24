import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import '../../support/fixtures/widget_environment_fixture.dart';
import 'object_route_access_cases.dart' show ObjectFixture, mount;

void main() {
  WidgetEnvironmentFixture.register();
  late WidgetEnvironmentFixture environment;
  setUpAll(() {
    environment = WidgetEnvironmentFixture(
        locale: const Locale('cs'),
        translations:
            jsonDecode(File('assets/translations/cs.json').readAsStringSync())
                as Map<String, dynamic>);
  });
  testWidgetsWithEnvironment(
      () => environment, 'dirty bank dialog can cancel barrier dismissal',
      (tester) async {
    final router = ObjectFixture()..realBankGeneral = true;
    await mount(tester, router, '/unit/5/edit/bank-accounts/9/general',
        environment: environment);
    final title = find.widgetWithText(TextFormField, 'Unit account');
    await tester.enterText(title, 'Unsaved title');
    await tester.tapAt(const Offset(10, 10));
    await tester.pumpAndSettle();
    expect(find.byType(AlertDialog), findsOneWidget);
    await tester.tap(find.descendant(
        of: find.byType(AlertDialog),
        matching: find.widgetWithText(TextButton, 'Storno')));
    await tester.pumpAndSettle();
    expect(router.currentUrl, '/unit/5/edit/bank-accounts/9/general');
    expect(find.text('Unsaved title'), findsOneWidget);
  });
}
