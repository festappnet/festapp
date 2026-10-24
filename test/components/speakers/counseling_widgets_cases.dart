import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fstapp/components/speakers/speaker_topic_model.dart';
import 'package:fstapp/components/speakers/topic_picker.dart';

/// Widget tests for the counseling area picker. `.tr()` returns raw keys in the
/// test env, so localized labels are asserted by key.

Future<void> _pumpTopicPicker(
  WidgetTester tester, {
  required List<SpeakerTopicModel> topics,
  required void Function(int) onChanged,
  int? initial,
  Set<int>? availableTopicIds,
  Map<int, ({int occupied, int total})>? occupancyByTopic,
}) async {
  int? selected = initial;
  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: StatefulBuilder(
          builder: (context, setState) => TopicPicker(
            topics: topics,
            selectedTopicId: selected,
            availableTopicIds: availableTopicIds,
            occupancyByTopic: occupancyByTopic,
            onSelected: (v) {
              setState(() => selected = v);
              onChanged(v);
            },
          ),
        ),
      ),
    ),
  );
}

void main() {
  group('TopicPicker', () {
    final topics = [
      SpeakerTopicModel(id: 10, title: 'A'),
      SpeakerTopicModel(id: 11, title: 'B'),
    ];

    testWidgets('is single-select: choosing a second option deselects the first',
        (tester) async {
      final picked = <int>[];
      await _pumpTopicPicker(tester, topics: topics, onChanged: picked.add);

      int? groupValue() =>
          tester.widget<RadioGroup<int>>(find.byType(RadioGroup<int>)).groupValue;

      await tester.tap(find.text('A'));
      await tester.pumpAndSettle();
      expect(picked.last, 10);
      expect(groupValue(), 10);

      await tester.tap(find.text('B'));
      await tester.pumpAndSettle();
      expect(picked.last, 11);
      // Single-select: the group now holds B only, so A is deselected.
      expect(groupValue(), 11);
    });

    testWidgets('greys out areas with no free slots but keeps them tappable',
        (tester) async {
      final picked = <int>[];
      await _pumpTopicPicker(tester,
          topics: topics,
          onChanged: picked.add,
          availableTopicIds: const {10}); // only A has free slots

      // The unavailable area is rendered at reduced opacity (greyed).
      final hasGreyed = tester
          .widgetList<Opacity>(find.byType(Opacity))
          .any((o) => (o.opacity - 0.45).abs() < 0.001);
      expect(hasGreyed, isTrue);

      // Greyed areas stay clickable (revealing the empty state).
      await tester.tap(find.text('B'));
      await tester.pumpAndSettle();
      expect(picked.last, 11);
    });

    testWidgets('shows occupancy as a trailing capacity badge', (tester) async {
      await _pumpTopicPicker(tester,
          topics: topics,
          onChanged: (_) {},
          availableTopicIds: const {10, 11},
          occupancyByTopic: const {
            10: (occupied: 8, total: 20),
            11: (occupied: 2, total: 5),
          });

      // The classic "occupied/total" capacity text appears per area.
      expect(find.text('8/20'), findsOneWidget);
      expect(find.text('2/5'), findsOneWidget);
    });
  });
}
