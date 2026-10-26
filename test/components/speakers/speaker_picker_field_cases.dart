import 'package:fstapp/widgets/dependency_material_bridge.dart';
import '../../support/fixtures/localization_log_fixture.dart';
import 'package:material_ui/material_ui.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fstapp/components/speakers/admin/speaker_picker_field.dart';
import 'package:fstapp/components/speakers/speaker_model.dart';

/// Widget tests for SpeakerPickerField. `.tr()` returns raw keys in the test
/// env, so localized labels are asserted by key. The widget is pure (data +
/// callbacks injected, no RPC), so it pumps directly.

final _speakers = [
  SpeakerModel(id: 1, title: 'Řehoř Novák', subtitle: 'psycholog'),
  SpeakerModel(id: 2, title: 'Jan Dvořák', subtitle: 'kněz'),
  SpeakerModel(id: 3, title: 'Petr Malý', subtitle: 'lékař'),
];

Widget _wrap(Widget child) => MaterialApp(builder: DependencyMaterialBridge.builder, home: Scaffold(body: child));

void main() {
  // This suite intentionally uses untranslated key fallback (no catalog).
  setUp(() {
    final logs = LocalizationLogFixture.install(expectedMissingCatalog: true);
    addTearDown(logs.dispose);
  });
  testWidgets('renders selected speakers as avatar chips with names',
      (tester) async {
    await tester.pumpWidget(_wrap(SpeakerPickerField(
      allSpeakers: _speakers,
      selectedIds: const [1, 2],
      onChanged: (_) {},
    )));

    expect(find.text('Řehoř Novák'), findsOneWidget);
    expect(find.text('Jan Dvořák'), findsOneWidget);
    expect(find.text('Petr Malý'), findsNothing); // not selected
    expect(find.byType(InputChip), findsNWidgets(2));
  });

  testWidgets('empty selection shows the placeholder', (tester) async {
    await tester.pumpWidget(_wrap(SpeakerPickerField(
      allSpeakers: _speakers,
      selectedIds: const [],
      onChanged: (_) {},
    )));

    expect(find.text('Speakers.selectSpeakers'), findsOneWidget);
    expect(find.byType(InputChip), findsNothing);
  });

  testWidgets('removing a chip calls onChanged without that id',
      (tester) async {
    List<int>? changed;
    await tester.pumpWidget(_wrap(SpeakerPickerField(
      allSpeakers: _speakers,
      selectedIds: const [1, 2],
      onChanged: (ids) => changed = ids,
    )));

    // The first chip (id 1) is rendered first; tap its × (delete) icon.
    await tester.tap(find.byIcon(Icons.close).first);
    await tester.pumpAndSettle();

    expect(changed, isNotNull);
    expect(changed!.contains(1), isFalse);
    expect(changed!.contains(2), isTrue);
  });

  testWidgets('dialog search filters by name (diacritics-insensitive)',
      (tester) async {
    // Areas/speakers are matched by NAME only — role is not part of the search
    // (organizer decision 2026-07-10).
    await tester.pumpWidget(_wrap(SpeakerPickerField(
      allSpeakers: _speakers,
      selectedIds: const [],
      onChanged: (_) {},
    )));

    await tester.tap(find.text('Speakers.selectSpeakers'));
    await tester.pumpAndSettle();
    expect(find.byType(CheckboxListTile), findsNWidgets(3));

    // Name match, no diacritics in the query: 'rehor' → 'Řehoř Novák'.
    await tester.enterText(find.byType(TextField), 'rehor');
    await tester.pumpAndSettle();
    expect(find.byType(CheckboxListTile), findsOneWidget);
    expect(find.text('Řehoř Novák'), findsOneWidget);

    // Another name match (diacritics-insensitive): 'dvorak' → 'Jan Dvořák'.
    await tester.enterText(find.byType(TextField), 'dvorak');
    await tester.pumpAndSettle();
    expect(find.byType(CheckboxListTile), findsOneWidget);
    expect(find.text('Jan Dvořák'), findsOneWidget);
  });

  testWidgets('confirming the dialog returns the selected ids', (tester) async {
    List<int>? changed;
    await tester.pumpWidget(_wrap(SpeakerPickerField(
      allSpeakers: _speakers,
      selectedIds: const [],
      onChanged: (ids) => changed = ids,
    )));

    await tester.tap(find.text('Speakers.selectSpeakers'));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Řehoř Novák'));
    await tester.tap(find.text('Petr Malý'));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Common.ok'));
    await tester.pumpAndSettle();

    expect(changed, isNotNull);
    expect(changed!.toSet(), {1, 3});
  });

  testWidgets(
      'Add speaker invokes onAddSpeaker; the new speaker is pre-selected',
      (tester) async {
    var addCalled = false;
    final speakers = [..._speakers];
    final selected = <int>[];

    // A stateful host mimics event_edit_page: onAddSpeaker (the injected
    // callback) creates a speaker + refreshes the list, then onChanged rebuilds
    // with the new selection (decision R6 / scenario f).
    await tester.pumpWidget(_wrap(StatefulBuilder(
      builder: (context, setState) => SpeakerPickerField(
        allSpeakers: speakers,
        selectedIds: selected,
        onChanged: (ids) => setState(() {
          selected
            ..clear()
            ..addAll(ids);
        }),
        onAddSpeaker: () async {
          addCalled = true;
          speakers.add(
              SpeakerModel(id: 4, title: 'Nový Poradce', subtitle: 'terapeut'));
          return 4;
        },
      ),
    )));

    await tester.tap(find.text('Speakers.selectSpeakers'));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Speakers.addSpeaker'));
    await tester.pumpAndSettle();

    expect(addCalled, isTrue);
    // Dialog closed; the new speaker is selected and rendered as a chip.
    expect(selected.contains(4), isTrue);
    expect(find.text('Nový Poradce'), findsOneWidget);
    expect(find.byType(InputChip), findsOneWidget);
  });
}
