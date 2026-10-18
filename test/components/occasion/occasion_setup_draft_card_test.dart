import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fstapp/components/_shared/common_strings.dart';
import 'package:fstapp/components/occasion/setup/occasion_setup_draft.dart';
import 'package:fstapp/components/occasion/setup/occasion_setup_strings.dart';
import 'package:fstapp/components/unit/views/occasion_setup_draft_card.dart';
import '../../support/fixtures/widget_environment_fixture.dart';

late WidgetEnvironmentFixture environment;
OccasionSetupDraft draft(String title) => OccasionSetupDraft.fromJson({
      'id': '00000000-0000-4000-8000-000000000001',
      'unit': 1,
      'revision': 2,
      'current_step': 1,
      'data': {
        'title': title,
        'completed': [0, 1]
      },
    });

void main() {
  WidgetEnvironmentFixture.register();
  setUpAll(() => environment = WidgetEnvironmentFixture(
      locale: const Locale('cs'),
      translations:
          jsonDecode(File('assets/translations/cs.json').readAsStringSync())
              as Map<String, dynamic>));

  testWidgetsWithEnvironment(() => environment,
      'discard requires confirmation and blocks only its pending card',
      (tester) async {
    var resumed = 0;
    var deleted = 0;
    final pending = Completer<void>();
    await environment.pumpWidget(
        tester,
        MaterialApp(
            home: Scaffold(
                body: SizedBox(
                    width: 400,
                    height: 184,
                    child: OccasionSetupDraftCard(
                        draft: draft('Ples'),
                        onResume: () => resumed++,
                        onDelete: () {
                          deleted++;
                          return pending.future;
                        })))));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Ples'));
    await tester.pumpAndSettle();
    expect(resumed, 1);
    Future<void> openConfirmation() async {
      await tester.tap(find.byType(PopupMenuButton<String>));
      await tester.pumpAndSettle();
      await tester.tap(find.text(OccasionSetupStrings.cancelDraft));
      await tester.pumpAndSettle();
    }

    await openConfirmation();
    expect(deleted, 0);
    expect(find.textContaining('Ples'), findsWidgets);
    await tester.tap(find.text(CommonStrings.back));
    await tester.pumpAndSettle();
    expect(deleted, 0);
    await openConfirmation();
    await tester.tap(
        find.widgetWithText(ElevatedButton, OccasionSetupStrings.cancelDraft));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    expect(deleted, 1);
    expect(find.byType(CircularProgressIndicator), findsOneWidget);
    expect(
        tester
            .widget<PopupMenuButton<String>>(
                find.byType(PopupMenuButton<String>))
            .enabled,
        false);
    await tester.tap(find.text('Ples'));
    expect(resumed, 1);
    pending.complete();
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });

  for (final dark in [false, true]) {
    testWidgetsWithEnvironment(() => environment,
        'draft fits narrow viewport with enlarged text dark=$dark',
        (tester) async {
      tester.view.physicalSize = const Size(320, 900);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await environment.pumpWidget(
          tester,
          MaterialApp(
              theme: dark ? ThemeData.dark() : ThemeData.light(),
              home: MediaQuery(
                  data: const MediaQueryData(textScaler: TextScaler.linear(2)),
                  child: Scaffold(
                      body: Padding(
                          padding: const EdgeInsets.all(16),
                          child: SizedBox(
                              height: 368,
                              child: OccasionSetupDraftCard(
                                  draft: draft(
                                      'Dlouhý název rozpracované události pro pořadatele'),
                                  onResume: () {},
                                  onDelete: () async {})))))));
      await tester.pumpAndSettle();
      expect(find.text(OccasionSetupStrings.resume), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  }
}
