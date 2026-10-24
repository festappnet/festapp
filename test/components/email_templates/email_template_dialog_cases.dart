import '../../support/fixtures/localization_log_fixture.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fstapp/components/email_templates/db_email_templates.dart';
import 'package:fstapp/components/email_templates/email_template_model.dart';
import 'package:fstapp/components/email_templates/views/email_templates_settings_page.dart';
import 'package:fstapp/components/html/rich_html_editor_dialog.dart';
import 'package:fstapp/components/unit/unit_model.dart';
import 'package:fstapp/widgets/app_dialog.dart';

Future<void> openTemplate(WidgetTester tester) async {
  await tester.pumpWidget(MaterialApp(
    home: Scaffold(
      body: Builder(
        builder: (context) => TextButton(
          onPressed: () => showDialog<void>(
            context: context,
            builder: (_) => EmailTemplateSettingsPage(
              template: EmailTemplateModel(
                code: 'SIGN_IN_CODE',
                subject: 'Subject',
                html: '<p>Content</p>',
              ),
              emailTemplatesResponse: EmailTemplatesResponse(
                unit: UnitModel(id: 1, title: 'Unit'),
                organization: UnitModel(id: 2, title: 'Organization'),
                templates: [],
              ),
            ),
          ),
          child: const Text('Open'),
        ),
      ),
    ),
  ));
  await tester.tap(find.text('Open'));
  await tester.pumpAndSettle();
}

void main() {
  // This suite intentionally uses untranslated key fallback (no catalog).
  setUp(() {
    final logs = LocalizationLogFixture.install(expectedMissingCatalog: true);
    addTearDown(logs.dispose);
  });
  for (final width in [320.0, 1200.0]) {
    testWidgets('email settings use the shared modal at width $width',
        (tester) async {
      tester.view.physicalSize = Size(width, 800);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await openTemplate(tester);
      expect(find.byType(AppAlertDialog), findsOneWidget);
      expect(find.byType(AppDialogHeader), findsOneWidget);
      expect(find.byIcon(Icons.close), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pumpAndSettle();
      expect(find.byType(EmailTemplateSettingsPage), findsNothing);
    });
  }

  testWidgets('email HTML expands into the same editor as field descriptions',
      (tester) async {
    tester.view.physicalSize = const Size(1200, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await openTemplate(tester);
    await tester.scrollUntilVisible(find.byIcon(Icons.edit), 200,
        scrollable: find
            .descendant(
                of: find.byType(ListView), matching: find.byType(Scrollable))
            .first);
    await tester.tap(find.byIcon(Icons.edit));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.byIcon(Icons.open_in_full));
    await tester.tap(find.byIcon(Icons.open_in_full));
    await tester.pumpAndSettle();
    expect(find.byType(RichHtmlEditorDialog), findsOneWidget);
    expect(find.byType(AppDialogAppBar), findsOneWidget);
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();
    expect(find.byType(RichHtmlEditorDialog), findsNothing);
    expect(find.byType(EmailTemplateSettingsPage), findsOneWidget);
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();
    expect(find.byType(EmailTemplateSettingsPage), findsNothing);
    expect(tester.takeException(), isNull);
  });
}
