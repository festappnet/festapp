import 'package:fstapp/widgets/dependency_material_bridge.dart';
import '../../support/fixtures/localization_log_fixture.dart';
import 'dart:async';

import 'package:material_ui/material_ui.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fstapp/components/event_feedback/event_feedback_model.dart';
import 'package:fstapp/components/event_feedback/event_feedback_widget.dart';

/// Verifies the per-event feedback UI matches the deployed csmostrava build:
/// bordered container, three equal-width smiley tiles, submit disabled until a
/// rating is chosen, and the already-rated state (preselected tile, "update"
/// label, remove button). `.tr()` returns raw keys in the test env, so labels
/// are asserted by key.
Future<void> _pump(
  WidgetTester tester, {
  required bool isOpen,
  bool isEditorPreview = false,
  bool requiresSignIn = false,
  bool isParticipant = false,
  EventFeedbackModel? existing,
  Future<EventFeedbackModel?> Function(int eventId)? loadFeedback,
  Future<bool> Function()? isOffline,
  Future<Map<String, dynamic>?> Function(int eventId)? loadCachedFeedback,
  Duration loadTimeout = const Duration(seconds: 12),
  bool settle = true,
}) async {
  await tester.pumpWidget(
    MaterialApp(builder: DependencyMaterialBridge.builder,
      home: Scaffold(
        body: EventFeedbackWidget(
          eventId: 1,
          isOpen: isOpen,
          isEditorPreview: isEditorPreview,
          requiresSignIn: requiresSignIn,
          isParticipant: isParticipant,
          loadFeedbackOverride: loadFeedback ?? (_) async => existing,
          isOfflineOverride: isOffline ?? () async => false,
          loadCachedFeedbackOverride: loadCachedFeedback ?? (_) async => null,
          loadTimeout: loadTimeout,
          saveCachedFeedbackOverride: (_, __) async {},
        ),
      ),
    ),
  );
  if (settle) {
    await tester.pumpAndSettle();
  } else {
    await tester.pump();
  }
}

EventFeedbackModel _rated(String rating, {String? note}) =>
    EventFeedbackModel(id: 5, event: 1, rating: rating, note: note);

FilledButton _submitButton(WidgetTester tester) =>
    tester.widget<FilledButton>(find.byType(FilledButton));

void main() {
  // This suite intentionally uses untranslated key fallback (no catalog).
  setUp(() {
    final logs = LocalizationLogFixture.install(expectedMissingCatalog: true);
    addTearDown(logs.dispose);
  });
  testWidgets('known offline state never waits on the remote feedback request',
      (tester) async {
    final neverCompletes = Completer<EventFeedbackModel?>();
    var remoteCalls = 0;

    await _pump(
      tester,
      isOpen: true,
      loadFeedback: (_) {
        remoteCalls++;
        return neverCompletes.future;
      },
      isOffline: () async => true,
      loadCachedFeedback: (_) async => null,
    );

    expect(remoteCalls, 0);
    expect(find.byType(CircularProgressIndicator), findsNothing);
    expect(find.text('Offline.feedbackStateUnknown'), findsOneWidget);
  });

  testWidgets('a feedback timeout leaves loading and shows offline state',
      (tester) async {
    await _pump(
      tester,
      isOpen: true,
      loadFeedback: (_) async => throw TimeoutException('feedback load'),
      isOffline: () async => false,
      loadCachedFeedback: (_) async => null,
    );

    expect(find.byType(CircularProgressIndicator), findsNothing);
    expect(find.text('Offline.feedbackStateUnknown'), findsOneWidget);
  });

  testWidgets('closed window shows the "opens when starts" message, no tiles',
      (tester) async {
    await _pump(tester, isOpen: false);

    expect(find.text('EventFeedback.feedbackOpensWhenEventStarts'),
        findsOneWidget);
    // No rating tiles and no submit button while closed.
    expect(find.byType(FilledButton), findsNothing);
    expect(find.byIcon(Icons.sentiment_very_satisfied), findsNothing);
  });

  testWidgets('open + not yet rated: three tiles, submit disabled, no remove',
      (tester) async {
    await _pump(tester, isOpen: true);

    // Three semantic smiley tiles.
    expect(find.byIcon(Icons.sentiment_very_satisfied), findsOneWidget);
    expect(find.byIcon(Icons.sentiment_neutral), findsOneWidget);
    expect(find.byIcon(Icons.sentiment_very_dissatisfied), findsOneWidget);

    // Submit is disabled until a rating is chosen (matches production).
    expect(_submitButton(tester).onPressed, isNull);
    expect(find.text('EventFeedback.sendFeedback'), findsOneWidget);

    // Remove button is absent when nothing is entered.
    expect(find.widgetWithText(TextButton, 'EventFeedback.removeFeedback'),
        findsNothing);
  });

  testWidgets('choosing a rating enables submit', (tester) async {
    await _pump(tester, isOpen: true);
    expect(_submitButton(tester).onPressed, isNull);

    await tester.tap(find.byIcon(Icons.sentiment_neutral));
    await tester.pumpAndSettle();

    expect(_submitButton(tester).onPressed, isNotNull);
    // Remove appears once a rating is picked.
    expect(find.text('EventFeedback.removeFeedback'), findsOneWidget);
  });

  testWidgets(
      'already rated (signed-in): tile preselected, update label, remove',
      (tester) async {
    await _pump(tester,
        isOpen: true, existing: _rated('happy', note: 'super akce'));

    // Existing note is prefilled.
    expect(find.text('super akce'), findsOneWidget);

    // Submit is enabled and reads "update" (not "send").
    expect(_submitButton(tester).onPressed, isNotNull);
    expect(find.text('EventFeedback.updateFeedback'), findsOneWidget);
    expect(find.text('EventFeedback.sendFeedback'), findsNothing);

    // Remove is offered for an existing rating.
    expect(find.text('EventFeedback.removeFeedback'), findsOneWidget);
  });

  testWidgets('editing the comment after rating switches to "save comment"',
      (tester) async {
    await _pump(tester, isOpen: true, existing: _rated('sad', note: 'puvodni'));
    expect(find.text('EventFeedback.updateFeedback'), findsOneWidget);

    await tester.enterText(find.byType(TextField), 'novy komentar');
    await tester.pumpAndSettle();

    expect(find.text('EventFeedback.saveComment'), findsOneWidget);
    expect(find.text('EventFeedback.updateFeedback'), findsNothing);
  });

  testWidgets('capped event, non-participant: shows participants-only message',
      (tester) async {
    await _pump(tester, isOpen: true, requiresSignIn: true);

    expect(find.text('EventFeedback.onlySignedInParticipants'), findsOneWidget);
    // Form is hidden: no tiles, no submit.
    expect(find.byIcon(Icons.sentiment_very_satisfied), findsNothing);
    expect(find.byType(FilledButton), findsNothing);
  });

  testWidgets('capped event, participant: shows the form', (tester) async {
    await _pump(tester,
        isOpen: true, requiresSignIn: true, isParticipant: true);

    expect(find.text('EventFeedback.onlySignedInParticipants'), findsNothing);
    expect(find.byIcon(Icons.sentiment_very_satisfied), findsOneWidget);
    expect(find.byType(FilledButton), findsOneWidget);
  });

  testWidgets('capped event, editor: previews the form despite no sign-in',
      (tester) async {
    await _pump(tester,
        isOpen: true, requiresSignIn: true, isEditorPreview: true);

    expect(find.text('EventFeedback.onlySignedInParticipants'), findsNothing);
    // Editors get the form (its comment field) plus the results panel, so the
    // sentiment icon is not a unique finder here — assert the form's TextField.
    expect(find.byType(TextField), findsOneWidget);
  });

  testWidgets('outer chrome is a bordered container, not a Card',
      (tester) async {
    await _pump(tester, isOpen: true);
    expect(find.byType(Card), findsNothing);
    expect(find.byType(LayoutBuilder), findsWidgets);
  });
}
