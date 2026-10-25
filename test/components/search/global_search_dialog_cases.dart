import 'package:fstapp/widgets/dependency_material_bridge.dart';
import '../../support/fixtures/localization_log_fixture.dart';
import 'dart:async';

import 'package:material_ui/material_ui.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fstapp/components/search/global_search_dialog.dart';
import 'package:fstapp/components/search/search_result_model.dart';
import 'package:fstapp/components/speakers/speaker_avatar.dart';
import 'package:fstapp/components/speakers/speaker_model.dart';
import 'package:fstapp/components/speakers/speakers_bundle.dart';
import 'package:fstapp/data_services/client_sync/client_sync_runtime.dart';

void main() {
  // This suite intentionally uses untranslated key fallback (no catalog).
  setUp(() {
    final logs = LocalizationLogFixture.install(expectedMissingCatalog: true);
    addTearDown(logs.dispose);
  });
  testWidgets('open search refreshes when a new projection is activated',
      (tester) async {
    var title = 'Původní program';
    await tester.pumpWidget(MaterialApp(builder: DependencyMaterialBridge.builder,
      home: Builder(builder: (context) {
        return TextButton(
          onPressed: () => showDialog<void>(
            context: context,
            builder: (_) => GlobalSearchDialog(
              loadEvents: () async => [],
              search: (_) async => [
                SearchResultModel(
                  entityType: 'info',
                  entityId: 1,
                  title: title,
                ),
              ],
              loadSpeakers: () async => null,
            ),
          ),
          child: const Text('Search'),
        );
      }),
    ));

    await tester.tap(find.text('Search'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), 'program');
    await tester.pump(const Duration(milliseconds: 300));
    await tester.pumpAndSettle();
    expect(find.text('Původní program'), findsOneWidget);

    title = 'Nově synchronizovaný program';
    ClientSyncRuntime.projectionEpoch.value++;
    await tester.pumpAndSettle();

    expect(find.text('Původní program'), findsNothing);
    expect(find.text('Nově synchronizovaný program'), findsOneWidget);
  });

  testWidgets('speaker without an event still opens a profile', (tester) async {
    final speakers = Completer<SpeakersBundle?>();
    await tester.pumpWidget(MaterialApp(builder: DependencyMaterialBridge.builder,
      home: Builder(builder: (context) {
        return TextButton(
          onPressed: () => showDialog<void>(
            context: context,
            builder: (_) => GlobalSearchDialog(
              loadEvents: () async => [],
              search: (_) async => [
                SearchResultModel(
                  entityType: 'speaker',
                  entityId: 42,
                  title: 'Jan Bez Programu',
                  snippet: 'psychoterapeut',
                ),
              ],
              loadSpeakers: () => speakers.future,
            ),
          ),
          child: const Text('Search'),
        );
      }),
    ));

    await tester.tap(find.text('Search'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), 'jan');
    await tester.pump(const Duration(milliseconds: 300));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Jan Bez Programu'));
    await tester.pump();
    expect(find.byKey(const Key('speaker-profile-dialog')), findsNothing);

    speakers.complete(SpeakersBundle(
      speakers: [
        SpeakerModel(
          id: 42,
          title: 'Jan Bez Programu',
          subtitle: 'psychoterapeut',
          image: 'https://img.festapp.net/jan.jpg',
        ),
      ],
      topics: const [],
      topicsBySpeaker: const {},
      speakersByTopic: const {},
      speakersByEvent: const {},
    ));
    await tester.pumpAndSettle();

    final profile = find.byKey(const Key('speaker-profile-dialog'));
    expect(profile, findsOneWidget);
    expect(
      find.descendant(of: profile, matching: find.text('Jan Bez Programu')),
      findsOneWidget,
    );
    expect(
      find.descendant(of: profile, matching: find.text('psychoterapeut')),
      findsOneWidget,
    );
    expect(
      tester.widget<SpeakerAvatar>(find.byType(SpeakerAvatar)).imageUrl,
      'https://img.festapp.net/jan.jpg',
    );
  });
}
