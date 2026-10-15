import '../../support/fixtures/localization_log_fixture.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fstapp/components/news/news_send_confirmation_dialog.dart';

Future<void> _pumpDialog(
  WidgetTester tester, {
  required bool isSelfOnly,
  bool isTest = false,
}) async {
  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: NewsSendConfirmationDialog(
          isSelfOnly: isSelfOnly,
          isTest: isTest,
          recipientIdentity: 'Marie Nováková · marie@example.com',
          heading: 'Změna programu',
          htmlContent: '<p>Začínáme <strong>o hodinu dříve</strong>.</p>',
        ),
      ),
    ),
  );
}

void main() {
  // This suite intentionally uses untranslated key fallback (no catalog).
  setUp(() {
    final logs = LocalizationLogFixture.install(expectedMissingCatalog: true);
    addTearDown(logs.dispose);
  });
  testWidgets('self-only confirmation makes recipient explicit',
      (tester) async {
    await _pumpDialog(tester, isSelfOnly: true, isTest: true);

    expect(find.byIcon(Icons.notifications_active_outlined), findsOneWidget);
    expect(find.text('FeatureNews.confirmTestSendTitle'), findsOneWidget);
    expect(find.text('FeatureNews.testSendExplanation'), findsOneWidget);
    expect(find.text('FeatureNews.notificationAudienceSelf'), findsOneWidget);
    expect(
      find.text('Marie Nováková · marie@example.com'),
      findsOneWidget,
    );
    expect(
      find.text('FeatureNews.notificationCannotBeRecalled'),
      findsOneWidget,
    );
    expect(find.text('Začínáme o hodinu dříve.'), findsOneWidget);
  });

  testWidgets('public send confirmation identifies the broad audience',
      (tester) async {
    await _pumpDialog(tester, isSelfOnly: false);

    expect(find.byIcon(Icons.notifications_active_outlined), findsOneWidget);
    expect(find.text('FeatureNews.confirmSendTitle'), findsOneWidget);
    expect(
      find.text('FeatureNews.notificationAudienceEveryone'),
      findsOneWidget,
    );
    expect(
      find.text('FeatureNews.notificationAudienceEveryoneDetail'),
      findsOneWidget,
    );
    expect(
      find.text('FeatureNews.notificationCannotBeRecalled'),
      findsOneWidget,
    );
  });
}
