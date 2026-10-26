import 'package:fstapp/widgets/dependency_material_bridge.dart';
import '../../support/fixtures/localization_log_fixture.dart';
import 'package:material_ui/material_ui.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fstapp/components/news/news_notification_audience_selector.dart';

Future<void> _pumpSelector(
  WidgetTester tester, {
  NewsNotificationAudience? selected,
  bool allowEveryone = true,
  required ValueChanged<NewsNotificationAudience> onChanged,
}) async {
  await tester.pumpWidget(
    MaterialApp(builder: DependencyMaterialBridge.builder,
      home: Scaffold(
        body: SingleChildScrollView(
          child: NewsNotificationAudienceSelector(
            selected: selected,
            onChanged: onChanged,
            currentUserIdentity: 'Marie · marie@example.com',
            allowEveryone: allowEveryone,
          ),
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
  testWidgets('shows no-push, everyone and self-test as explicit choices',
      (tester) async {
    NewsNotificationAudience? chosen;
    await _pumpSelector(
      tester,
      onChanged: (value) => chosen = value,
    );

    expect(find.text('FeatureNews.newsWithoutNotification'), findsOneWidget);
    expect(find.text('FeatureNews.notificationAudienceSelf'), findsOneWidget);
    expect(
      find.text('FeatureNews.notificationAudienceEveryone'),
      findsOneWidget,
    );
    expect(find.byIcon(Icons.check_circle), findsNothing);

    await tester.tap(find.text('FeatureNews.notificationAudienceSelf'));
    expect(chosen, NewsNotificationAudience.selfTest);
  });

  testWidgets('marks the chosen audience and can hide public delivery',
      (tester) async {
    await _pumpSelector(
      tester,
      selected: NewsNotificationAudience.selfTest,
      allowEveryone: false,
      onChanged: (_) {},
    );

    expect(find.byIcon(Icons.check_circle), findsOneWidget);
    expect(
      find.text('FeatureNews.notificationAudienceEveryone'),
      findsNothing,
    );
    expect(
      find.text('FeatureNews.notificationAudienceSelfDetail'),
      findsOneWidget,
    );
  });

  test('delivery modes keep publishing and self-test behavior distinct', () {
    const userId = 'current-user';

    expect(
      NewsNotificationAudience.none.deliveryFields(currentUserId: userId),
      {'with_notification': false},
    );
    expect(
      NewsNotificationAudience.everyone.deliveryFields(currentUserId: userId),
      {'with_notification': true},
    );
    expect(
      NewsNotificationAudience.selfTest.deliveryFields(currentUserId: userId),
      {
        'with_notification': true,
        'add_to_news': false,
        'to': [userId],
      },
    );
  });
}
