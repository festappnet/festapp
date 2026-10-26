import 'package:material_ui/material_ui.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:venue_seat_picker/venue_seat_picker.dart';
import 'package:venue_seat_picker/src/layout_editor/widgets/layout_inspector.dart';

Future<void> mountInspector(
  WidgetTester tester,
  VenueLayoutController c,
) async {
  addTearDown(c.dispose);
  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: SizedBox(
          width: 340,
          child: ListenableBuilder(
            listenable: c,
            builder: (_, _) => LayoutInspector(
              controller: c,
              cornerPivot: false,
              onPivotChanged: (_) {},
            ),
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('total count groups steppers and disables both boundary states', (
    tester,
  ) async {
    final original = tableLayout(
      shape: 'rectangle',
      count: 0,
      width: 240,
      height: 120,
    );
    final table = original.nodes.firstWhere((n) => n.kind == 'table');
    final c = VenueLayoutController(original)..select({table.id});
    await mountInspector(tester, c);
    final field = find.widgetWithText(TextField, 'Seats');
    await tester.ensureVisible(field);
    IconButton step(String label) => tester.widget<IconButton>(
      find
          .ancestor(
            of: find.byTooltip(label),
            matching: find.byType(IconButton),
          )
          .first,
    );
    final suffix = tester.widget<TextField>(field).decoration!.suffixIcon!;
    expect(suffix, isA<Row>());
    expect((suffix as Row).mainAxisSize, MainAxisSize.min);
    expect(suffix.children, hasLength(2));
    expect(step('Remove one seat').onPressed, isNull);
    expect(step('Add one seat').onPressed, isNotNull);
    expect(step('Top seats: Remove one seat').onPressed, isNull);
    final style = step('Remove one seat').style!;
    expect(
      style.foregroundColor!.resolve({WidgetState.disabled}),
      isNot(style.foregroundColor!.resolve({})),
    );
    final maximum = tableCapacity(table);
    await tester.enterText(field, '$maximum');
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pumpAndSettle();
    expect(c.document.nodes.where((n) => n.kind == 'seat'), hasLength(maximum));
    expect(step('Add one seat').onPressed, isNull);
    expect(step('Remove one seat').onPressed, isNotNull);
    for (final side in ['Top', 'Right', 'Bottom', 'Left']) {
      expect(step('$side seats: Add one seat').onPressed, isNull);
    }
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'side counts reject overflow while typing and allow clearing and replacing',
    (tester) async {
      final original = tableLayout(
        shape: 'rectangle',
        count: 6,
        width: 240,
        height: 120,
      );
      final table = original.nodes.firstWhere((n) => n.kind == 'table');
      final c = VenueLayoutController(original)..select({table.id});
      await mountInspector(tester, c);
      final field = find.widgetWithText(TextField, 'Top seats');
      await tester.ensureVisible(field);
      await tester.enterText(field, '15');
      expect(tester.widget<TextField>(field).controller!.text, isNot('15'));
      expect(c.error, isNull);
      await tester.enterText(field, '');
      expect(tester.widget<TextField>(field).controller!.text, isEmpty);
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await tester.pumpAndSettle();
      expect(tester.widget<TextField>(field).controller!.text, '2');
      await tester.enterText(field, '3');
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await tester.pumpAndSettle();
      expect(c.document.nodes.where((n) => n.kind == 'seat'), hasLength(7));
      expect(c.error, isNull);
    },
  );

  testWidgets(
    'reserved seats disable shrinking but allow adding and removing free seats',
    (tester) async {
      final original = tableLayout(
        shape: 'rectangle',
        count: 8,
        width: 240,
        height: 120,
      );
      final table = original.nodes.firstWhere((n) => n.kind == 'table');
      final reserved = original.nodes
          .where((n) => n.kind == 'seat')
          .map((n) => n.id)
          .toSet();
      final c = VenueLayoutController(
        original,
        protectedSeatIds: () => reserved,
      )..select({table.id});
      await mountInspector(tester, c);
      IconButton step(String label) => tester.widget<IconButton>(
        find
            .ancestor(
              of: find.byTooltip(label),
              matching: find.byType(IconButton),
            )
            .first,
      );
      expect(step('Remove one seat').onPressed, isNull);
      expect(step('Add one seat').onPressed, isNotNull);
      final field = find.widgetWithText(TextField, 'Seats');
      await tester.ensureVisible(field);
      await tester.enterText(field, '7');
      expect(tester.widget<TextField>(field).controller!.text, isNot('7'));
      await tester.enterText(field, '');
      expect(tester.widget<TextField>(field).controller!.text, isEmpty);
      await tester.enterText(field, '8');
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('Add one seat'));
      await tester.pumpAndSettle();
      expect(c.document.nodes.where((n) => n.kind == 'seat'), hasLength(9));
      final sideTotal =
          ['Top seats', 'Right seats', 'Bottom seats', 'Left seats']
              .map(
                (label) => int.parse(
                  tester
                      .widget<TextField>(find.widgetWithText(TextField, label))
                      .controller!
                      .text,
                ),
              )
              .fold<int>(0, (sum, value) => sum + value);
      expect(sideTotal, 9);
      expect(step('Remove one seat').onPressed, isNotNull);
      await tester.tap(find.byTooltip('Remove one seat'));
      await tester.pumpAndSettle();
      expect(
        c.document.nodes
            .where((n) => n.kind == 'seat')
            .map((n) => n.id)
            .toSet(),
        reserved,
      );
      expect(step('Remove one seat').onPressed, isNull);
      expect(c.error, isNull);
    },
  );

  testWidgets('side steppers use physical limits and reservation protection', (
    tester,
  ) async {
    var original = tableLayout(
      shape: 'rectangle',
      count: 8,
      width: 240,
      height: 120,
    );
    final table = original.nodes.firstWhere((n) => n.kind == 'table');
    original = reflowTable(original, table.id, 8, edgeCounts: [4, 0, 4, 0]);
    final reserved = original.nodes
        .where((n) => n.kind == 'seat')
        .map((n) => n.id)
        .toSet();
    final c = VenueLayoutController(original, protectedSeatIds: () => reserved)
      ..select({table.id});
    await mountInspector(tester, c);
    IconButton step(String label) => tester.widget<IconButton>(
      find
          .ancestor(
            of: find.byTooltip(label),
            matching: find.byType(IconButton),
          )
          .first,
    );
    expect(step('Top seats: Add one seat').onPressed, isNull);
    expect(step('Top seats: Remove one seat').onPressed, isNull);
    final add = find.byTooltip('Right seats: Add one seat');
    await tester.ensureVisible(add);
    expect(step('Right seats: Add one seat').onPressed, isNotNull);
    await tester.tap(add);
    await tester.pumpAndSettle();
    expect(c.document.nodes.where((n) => n.kind == 'seat'), hasLength(9));
    expect(
      c.document.nodes.map((n) => n.id).toSet().containsAll(reserved),
      isTrue,
    );
    expect(step('Right seats: Add one seat').onPressed, isNull);
    expect(c.error, isNull);
  });
  testWidgets('a protected minimum still permits typing a multi-digit count', (
    tester,
  ) async {
    final original = tableLayout(
      shape: 'rectangle',
      count: 8,
      width: 240,
      height: 120,
    );
    final table = original.nodes.firstWhere((n) => n.kind == 'table');
    final protected = original.nodes
        .where((n) => n.kind == 'seat')
        .map((n) => n.id)
        .toSet();
    final c = VenueLayoutController(original, protectedSeatIds: () => protected)
      ..select({table.id});
    await mountInspector(tester, c);
    final field = find.widgetWithText(TextField, 'Seats');
    await tester.ensureVisible(field);
    await tester.enterText(field, '');
    await tester.enterText(field, '1');
    expect(tester.widget<TextField>(field).controller!.text, '1');
    expect(c.document.nodes.where((n) => n.kind == 'seat'), hasLength(8));
    await tester.enterText(field, '10');
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pumpAndSettle();
    expect(c.document.nodes.where((n) => n.kind == 'seat'), hasLength(10));
    expect(
      c.document.nodes.map((n) => n.id).toSet().containsAll(protected),
      isTrue,
    );
    await tester.enterText(field, '1.5');
    expect(tester.widget<TextField>(field).controller!.text, '10');
    expect(c.error, isNull);
  });

  test('seat-count preflight is side-effect free and does not discard protected identities', () {
    final original = tableLayout(
      shape: 'rectangle',
      count: 8,
      width: 240,
      height: 120,
    );
    final table = original.nodes.firstWhere((n) => n.kind == 'table');
    final protected = original.nodes
        .where((n) => n.kind == 'seat')
        .map((n) => n.id)
        .toSet();
    final c = VenueLayoutController(
      original,
      protectedSeatIds: () => protected,
    );
    addTearDown(c.dispose);
    expect(c.canSetSeatCount(table.id, 7), isFalse);
    expect(c.canSetSeatCount(table.id, 9), isTrue);
    expect(c.document, same(original));
    expect(c.error, isNull);
    expect(c.canUndo, isFalse);
  });
  testWidgets(
    'side buttons commit a pending edit before stepping and keep totals synchronized',
    (tester) async {
      final original = tableLayout(
        shape: 'rectangle',
        count: 6,
        width: 240,
        height: 120,
      );
      final table = original.nodes.firstWhere((n) => n.kind == 'table');
      final c = VenueLayoutController(original)..select({table.id});
      await mountInspector(tester, c);
      final field = find.widgetWithText(TextField, 'Top seats');
      await tester.ensureVisible(field);
      await tester.enterText(field, '3');
      await tester.ensureVisible(find.byTooltip('Top seats: Add one seat'));
      await tester.tap(find.byTooltip('Top seats: Add one seat'));
      await tester.pumpAndSettle();
      expect(c.document.nodes.where((n) => n.kind == 'seat'), hasLength(8));
      expect(tester.widget<TextField>(field).controller!.text, '4');
      await tester.enterText(field, '');
      await tester.ensureVisible(find.byTooltip('Top seats: Remove one seat'));
      await tester.tap(find.byTooltip('Top seats: Remove one seat'));
      await tester.pumpAndSettle();
      expect(tester.widget<TextField>(field).controller!.text, '3');
      expect(c.document.nodes.where((n) => n.kind == 'seat'), hasLength(7));
      await tester.enterText(field, '4');
      await tester.ensureVisible(find.byTooltip('Top seats: Add one seat'));
      await tester.tap(find.byTooltip('Top seats: Add one seat'));
      await tester.pumpAndSettle();
      expect(tester.widget<TextField>(field).controller!.text, '4');
      expect(c.document.nodes.where((n) => n.kind == 'seat'), hasLength(8));
      expect(c.error, isNull);
    },
  );
}
