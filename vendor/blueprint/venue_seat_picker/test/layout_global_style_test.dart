import 'package:flutter/material.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:venue_seat_picker/venue_seat_picker.dart';
import 'package:venue_seat_picker/editor_ui.dart';
import 'package:venue_seat_picker/src/layout_editor/widgets/layout_appearance_preview.dart';
import 'package:venue_seat_picker/src/layout_editor/widgets/layout_appearance_families.dart';
import 'package:venue_seat_picker/src/layout_editor/widgets/layout_scene_surface.dart';
import 'package:venue_seat_picker/src/layout_editor/widgets/layout_global_style.dart';

void main() {
  Future<void> open(WidgetTester tester, VenueLayoutController c) async {
    addTearDown(c.dispose);
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => Scaffold(
            body: TextButton(
              onPressed: () => showLayoutGlobalStyleDialog(context, c),
              child: const Text('Open'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();
  }

  Future<void> customize(WidgetTester tester) async {
    await tester.ensureVisible(find.text('Fine-tune appearance'));
    await tester.tap(find.text('Fine-tune appearance'));
    await tester.pumpAndSettle();
  }

  testWidgets(
    'whole plan preset changes existing and future objects in one undo while keeping exceptions',
    (tester) async {
      final table = LayoutNode(
        id: newLayoutId(),
        kind: 'table',
        x: 100,
        y: 100,
      );
      final local = LayoutNode(
        id: newLayoutId(),
        kind: 'seat',
        x: 300,
        y: 200,
        properties: {
          'fill': '#123456FF',
          'appearanceOverrides': ['fill'],
        },
      );
      final c = VenueLayoutController(
        VenueLayoutDocument.empty().copyWith(nodes: [table, local]),
      );
      await open(tester, c);
      await tester.tap(find.text('Warm'));
      await tester.pump();
      expect(c.document.appearance.keys.toSet(), {
        'table',
        'seat',
        'shape',
        'furniture',
        'capacityArea',
        'text',
      });
      expect(c.document.canvas['fill'], '#FFFBF5FF');
      expect((c.document.appearance['seat'] as Map)['seatStyle'], isNull);
      expect(effectiveNodeProperties(c.document, table)['fill'], '#F0E4D2FF');
      expect(effectiveNodeProperties(c.document, local)['fill'], '#123456FF');
      final future = LayoutNode(
        id: newLayoutId(),
        kind: 'table',
        properties: {'fill': '#E2E8F0FF'},
      );
      expect(effectiveNodeProperties(c.document, future)['fill'], '#F0E4D2FF');
      c.undo();
      await tester.pump();
      expect(c.document.appearance, isEmpty);
      expect(c.document.canvas['fill'], '#FFFFFFFF');
      expect(c.canUndo, isFalse);
      expect(c.document.nodes.map((n) => n.id), [table.id, local.id]);
    },
  );

  testWidgets(
    'typed controls persist radius and width once and reject invalid values',
    (tester) async {
      final c = VenueLayoutController(VenueLayoutDocument.empty());
      await open(tester, c);
      await tester.tap(find.text('Appearance'));
      await tester.pumpAndSettle();
      await customize(tester);
      Finder field(String label) => find.descendant(
        of: find.byKey(
          ValueKey(
            'table-${label == 'Corner radius' ? 'cornerRadius' : 'strokeWidth'}',
          ),
        ),
        matching: find.byType(TextField),
      );
      await tester.ensureVisible(field('Corner radius'));
      await tester.enterText(field('Corner radius'), '12');
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await tester.pump();
      expect((c.document.appearance['table'] as Map)['cornerRadius'], 12);
      c.undo();
      await tester.pump();
      expect(c.canUndo, isFalse);
      expect(c.document.appearance, isEmpty);
      expect(c.document.canvas['fill'], '#FFFFFFFF');
      await tester.ensureVisible(field('Stroke width'));
      await tester.enterText(field('Stroke width'), '-3');
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await tester.pump();
      expect(find.text('Enter a non-negative number.'), findsOneWidget);
      expect(c.canUndo, isFalse);
      await tester.enterText(field('Stroke width'), '2.5');
      await tester.tap(find.text('Done'));
      await tester.pumpAndSettle();
      expect((c.document.appearance['table'] as Map)['strokeWidth'], 2.5);
      c.undo();
      expect(c.canUndo, isFalse);
    },
  );
  testWidgets('object-type selector limits edits to chosen scope', (
    tester,
  ) async {
    final c = VenueLayoutController(VenueLayoutDocument.empty());
    await open(tester, c);
    await tester.tap(find.text('Tables'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Chairs').last);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Appearance'));
    await tester.pumpAndSettle();
    await customize(tester);
    final stroke = find.descendant(
      of: find.byKey(const ValueKey('seat-strokeWidth')),
      matching: find.byType(TextField),
    );
    await tester.ensureVisible(stroke);
    await tester.enterText(stroke, '3');
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pump();
    expect(c.document.appearance.keys, ['seat']);
    expect((c.document.appearance['seat'] as Map)['strokeWidth'], 3);
    await tester.ensureVisible(find.text('Chairs'));
    await tester.tap(find.text('Chairs'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Text').last);
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('Colors'));
    await tester.tap(find.text('Colors'));
    await tester.pumpAndSettle();
    expect(find.text('Text color'), findsOneWidget);
    expect(
      find.byWidgetPredicate(
        (w) => w is TextField && w.decoration?.labelText == 'Corner radius',
      ),
      findsNothing,
    );
  });
  testWidgets(
    'shared color dialog includes plan colors and commits alpha once',
    (tester) async {
      final local = LayoutNode(
        id: newLayoutId(),
        kind: 'seat',
        properties: {'fill': '#123456FF'},
      );
      final c = VenueLayoutController(
        VenueLayoutDocument.empty().copyWith(nodes: [local]),
      );
      await open(tester, c);
      await tester.ensureVisible(find.text('Fill color'));
      await tester.tap(find.text('Fill color'));
      await tester.pumpAndSettle();
      final picker = tester.widget<EditorColorDialog>(
        find.byType(EditorColorDialog),
      );
      expect(picker.usedColors, contains('123456'));
      expect(picker.usedColors, contains('E2E8F0'));
      expect(picker.enableOpacity, isTrue);
      Navigator.of(tester.element(find.byType(EditorColorDialog))).pop(
        EditorColorResult(
          primary: EditorColorValue(hex: 'ABCDEF', opacity: .5),
        ),
      );
      await tester.pumpAndSettle();
      expect((c.document.appearance['table'] as Map)['fill'], '#ABCDEF80');
      c.undo();
      expect(c.document.appearance, isEmpty);
      expect(c.document.canvas['fill'], '#FFFFFFFF');
      expect(c.canUndo, isFalse);
    },
  );
  testWidgets(
    'global background color is independently editable and undoable',
    (tester) async {
      final c = VenueLayoutController(VenueLayoutDocument.empty());
      await open(tester, c);
      await tester.ensureVisible(find.text('Canvas color'));
      await tester.tap(find.text('Canvas color'));
      await tester.pumpAndSettle();
      final dialog = tester.element(find.byType(EditorColorDialog));
      Navigator.of(
        dialog,
      ).pop(EditorColorResult(primary: EditorColorValue(hex: 'F5EEE2')));
      await tester.pumpAndSettle();
      expect(c.document.canvas['fill'], '#F5EEE2FF');
      expect(c.document.appearance, isEmpty);
      c.undo();
      expect(c.document.canvas['fill'], '#FFFFFFFF');
      expect(c.canUndo, isFalse);
    },
  );
  testWidgets(
    'color palette preserves the chair appearance and geometry settings',
    (tester) async {
      final original = setLayoutAppearance(
        VenueLayoutDocument.empty(),
        'seat',
        {'seatStyle': 'wood', 'cornerRadius': 12, 'strokeWidth': 3},
      );
      final c = VenueLayoutController(original);
      await open(tester, c);
      await tester.tap(find.text('Warm'));
      await tester.pump();
      final seat = c.document.appearance['seat'] as Map;
      expect(seat['seatStyle'], 'wood');
      expect(seat['cornerRadius'], 12);
      expect(seat['strokeWidth'], 3);
      expect(seat['fill'], '#D9B788FF');
      c.undo();
      expect(c.document.toJson(), original.toJson());
    },
  );

  testWidgets('chair appearance changes independently of the chosen colors', (
    tester,
  ) async {
    final original = setLayoutAppearance(VenueLayoutDocument.empty(), 'seat', {
      'fill': '#123456FF',
    });
    final c = VenueLayoutController(original);
    await open(tester, c);
    await tester.ensureVisible(find.text('Tables'));
    await tester.tap(find.text('Tables'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Chairs').last);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Appearance'));
    await tester.pumpAndSettle();
    await customize(tester);
    expect(
      find.byKey(const ValueKey('global-appearance-preview')),
      findsOneWidget,
    );
    for (final family in layoutAppearanceFamilies) {
      expect(
        find.byKey(ValueKey('appearance-family-${family.id}')),
        findsOneWidget,
      );
    }
    await tester.ensureVisible(find.text('Wooden'));
    await tester.tap(find.text('Wooden').last);
    await tester.pumpAndSettle();
    expect((c.document.appearance['seat'] as Map)['seatStyle'], 'wood');
    expect((c.document.appearance['seat'] as Map)['fill'], '#123456FF');
    expect(c.document.canvas, original.canvas);
    c.undo();
    expect(c.document.toJson(), original.toJson());
  });
  testWidgets(
    'live specimen updates with appearance and never compiles the plan',
    (tester) async {
      final c = VenueLayoutController(
        tableLayout(shape: 'roundedRect', count: 40, width: 2000),
      );
      await open(tester, c);
      await tester.tap(find.text('Appearance'));
      await tester.pumpAndSettle();
      await customize(tester);
      Map<String, dynamic> scene() =>
          tester
                  .widget<CustomPaint>(
                    find.descendant(
                      of: find.byKey(
                        const ValueKey('global-appearance-preview'),
                      ),
                      matching: find.byType(CustomPaint),
                    ),
                  )
                  .painter
              is LayoutScenePainter
          ? (tester
                        .widget<CustomPaint>(
                          find.descendant(
                            of: find.byKey(
                              const ValueKey('global-appearance-preview'),
                            ),
                            matching: find.byType(CustomPaint),
                          ),
                        )
                        .painter
                    as LayoutScenePainter)
                .scene
          : throw StateError('Canonical painter missing');
      final before = scene();
      expect((before['items'] as List).length, lessThan(20));
      final ids = c.document.nodes.map((n) => n.id).toList();
      c.apply(setLayoutAppearance(c.document, 'table', {'cornerRadius': 20}));
      await tester.pump();
      expect(scene(), isNot(same(before)));
      expect(c.document.nodes.map((n) => n.id), ids);
    },
  );
  testWidgets('lounge combines with circular seats in one undoable action', (
    tester,
  ) async {
    final original = withLayoutMaterialFamily(
      tableLayout(shape: 'rect'),
      'round',
    );
    final c = VenueLayoutController(original);
    await open(tester, c);
    await tester.tap(find.text('Appearance'));
    await tester.pumpAndSettle();
    final round = find.byKey(const ValueKey('lounge-seat-true'));
    await tester.ensureVisible(round);
    await tester.tap(round);
    await tester.pumpAndSettle();
    expect(
      (c.document.appearance['seat'] as Map)['seatStyle'],
      'roundUpholstered',
    );
    expect((c.document.appearance['table'] as Map)['objectStyle'], 'lounge');
    expect(c.document.nodes, original.nodes);
    c.undo();
    await tester.pumpAndSettle();
    expect(c.document.toJson(), original.toJson());
    final family = layoutAppearanceFamilies.firstWhere(
      (family) => family.id == 'lounge',
    );
    expect(
      (withAppearanceFamily(original, family).appearance['seat']
          as Map)['seatStyle'],
      'roundUpholstered',
    );
    expect(
      (withAppearanceFamily(
            original,
            family,
            roundSeats: false,
          ).appearance['seat']
          as Map)['seatStyle'],
      'upholstered',
    );
  });

  Future<void> chairSettings(WidgetTester tester) async {
    final section = find.byKey(const ValueKey('plan-chair-layout'));
    await tester.ensureVisible(section);
    await tester.tap(find.text('Chair layout'));
    await tester.pumpAndSettle();
  }

  testWidgets(
    'chair sliders follow families and commit one edit after live preview',
    (tester) async {
      final original = tableLayout(
        shape: 'rect',
        count: 4,
        x: 600,
        y: 600,
        width: 400,
        height: 300,
      );
      final c = VenueLayoutController(original);
      await open(tester, c);
      await tester.tap(find.text('Appearance'));
      await tester.pumpAndSettle();
      expect(
        tester.getTopLeft(find.byType(LayoutAppearanceFamilies)).dy,
        lessThan(
          tester.getTopLeft(find.byKey(const ValueKey('plan-chair-layout'))).dy,
        ),
      );
      await chairSettings(tester);
      expect(find.byType(Slider), findsNWidgets(2));
      final slider = find.descendant(
        of: find.byKey(const ValueKey('plan-table-seatSize')),
        matching: find.byType(Slider),
      );
      await tester.ensureVisible(slider);
      await tester.pumpAndSettle();
      final control = tester.widget<Slider>(slider);
      control.onChangeStart!(40);
      control.onChanged!(120);
      await tester.pump();
      expect(tester.takeException(), isNull);
      tester.widget<Slider>(slider).onChanged!(52);
      await tester.pump();
      expect(c.document.toJson(), original.toJson());
      expect(c.canUndo, false);
      final preview = tester.widget<LayoutAppearancePreview>(
        find.descendant(
          of: find.byKey(const ValueKey('plan-chair-layout')),
          matching: find.byType(LayoutAppearancePreview),
        ),
      );
      expect(preview.appearance['table']!['seatWidth'], 52);
      expect(preview.appearance['table']!['seatHeight'], 52);
      tester.widget<Slider>(slider).onChangeEnd!(52);
      await tester.pumpAndSettle();
      expect(c.error, isNull);
      expect(documentSeating(c.document).width, 52);
      expect(
        c.document.nodes
            .where((n) => n.kind == 'seat')
            .every((n) => n.width == 52),
        true,
      );
      c.undo();
      expect(c.document.toJson(), original.toJson());
      expect(c.canUndo, false);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('double click resets a chair slider to its factory value', (
    tester,
  ) async {
    final original = configurePlanTableGap(
      tableLayout(
        shape: 'rect',
        count: 4,
        x: 600,
        y: 600,
        width: 400,
        height: 300,
      ),
      28,
    );
    final c = VenueLayoutController(original);
    await open(tester, c);
    await tester.tap(find.text('Appearance'));
    await tester.pumpAndSettle();
    await chairSettings(tester);
    final slider = find.descendant(
      of: find.byKey(const ValueKey('plan-table-seat-gap')),
      matching: find.byType(Slider),
    );
    await tester.ensureVisible(slider);
    await tester.pumpAndSettle();
    await tester.tap(slider);
    await tester.pump(const Duration(milliseconds: 80));
    await tester.tap(slider);
    await tester.pumpAndSettle();
    expect(documentSeating(c.document).gap, const TableSeating().gap);
    c.undo();
    expect(c.document.toJson(), original.toJson());
    expect(c.canUndo, false);
  });

  testWidgets(
    'preview chair count shows real capacity without editing or enlarging the plan',
    (tester) async {
      final original = tableLayout(shape: 'rect', count: 4, x: 600, y: 600);
      final c = VenueLayoutController(original);
      await open(tester, c);
      await tester.tap(find.text('Appearance'));
      await tester.pumpAndSettle();
      await chairSettings(tester);
      final preview = find.descendant(
        of: find.byKey(const ValueKey('plan-chair-layout')),
        matching: find.byType(LayoutAppearancePreview),
      );
      Map<String, dynamic> scene() =>
          (tester
                      .widget<CustomPaint>(
                        find.descendant(
                          of: preview,
                          matching: find.byType(CustomPaint),
                        ),
                      )
                      .painter
                  as LayoutScenePainter)
              .scene;
      List seats() => (scene()['items'] as List)
          .where((item) => item['kind'] == 'seat')
          .toList();
      final tableBefore = (scene()['items'] as List).singleWhere(
        (item) => item['kind'] == 'table',
      );
      expect(seats().length, 6);
      final more = find.byTooltip('More chairs');
      await tester.ensureVisible(more);
      await tester.pumpAndSettle();
      for (var i = 0; i < 18; i++) {
        await tester.tap(more);
        await tester.pump();
      }
      expect(seats().length, greaterThan(6));
      expect(seats().length, lessThan(24));
      expect(
        find.text('The table is full. Reduce the chair size or spacing.'),
        findsOneWidget,
      );
      final tableAfter = (scene()['items'] as List).singleWhere(
        (item) => item['kind'] == 'table',
      );
      expect(tableAfter, tableBefore);
      expect(c.document.toJson(), original.toJson());
      expect(c.canUndo, false);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'appearance sliders preview fractions, commit once and reset on double click',
    (tester) async {
      final original = VenueLayoutDocument.empty();
      final c = VenueLayoutController(original);
      await open(tester, c);
      await tester.tap(find.text('Appearance'));
      await tester.pumpAndSettle();
      await customize(tester);
      for (final entry in {
        'strokeWidth': 4.2,
        'cornerRadius': 17.0,
        'opacity': .75,
      }.entries) {
        final slider = find.descendant(
          of: find.byKey(ValueKey('table-${entry.key}')),
          matching: find.byType(Slider),
        );
        await tester.ensureVisible(slider);
        await tester.pumpAndSettle();
        final control = tester.widget<Slider>(slider);
        control.onChangeStart!(control.value);
        control.onChanged!(entry.value);
        await tester.pump();
        expect(c.document.toJson(), original.toJson());
        final preview = tester.widget<LayoutAppearancePreview>(
          find.byKey(const ValueKey('global-appearance-preview')),
        );
        expect(preview.appearance['table']![entry.key], entry.value);
        tester.widget<Slider>(slider).onChangeEnd!(entry.value);
        await tester.pumpAndSettle();
        expect((c.document.appearance['table'] as Map)[entry.key], entry.value);
        c.undo();
        await tester.pump();
        expect(c.document.toJson(), original.toJson());
        expect(c.canUndo, false);
      }
      final slider = find.descendant(
        of: find.byKey(const ValueKey('table-opacity')),
        matching: find.byType(Slider),
      );
      tester.widget<Slider>(slider).onChangeEnd!(.75);
      await tester.pump();
      await tester.ensureVisible(slider);
      await tester.pumpAndSettle();
      await tester.tap(slider);
      await tester.pump(const Duration(milliseconds: 80));
      await tester.tap(slider);
      await tester.pumpAndSettle();
      expect((c.document.appearance['table'] as Map)['opacity'], 1);
      c.undo();
      expect((c.document.appearance['table'] as Map)['opacity'], .75);
    },
  );

  testWidgets(
    'double click restores the selected family and object kind defaults',
    (tester) async {
      for (final scenario in [
        ('lounge', 'table', 'cornerRadius', 18.0),
        ('wood', 'table', 'strokeWidth', 1.2),
        ('minimal', 'seat', 'strokeWidth', 0.0),
        ('minimal', 'seat', 'cornerRadius', 8.0),
      ]) {
        final original = setLayoutAppearance(
          withLayoutMaterialFamily(VenueLayoutDocument.empty(), scenario.$1),
          scenario.$2,
          {scenario.$3: 5.0},
        );
        final c = VenueLayoutController(original);
        await open(tester, c);
        if (scenario.$2 == 'seat') {
          await tester.tap(find.text('Tables'));
          await tester.pumpAndSettle();
          await tester.tap(find.text('Chairs').last);
          await tester.pumpAndSettle();
        }
        await tester.tap(find.text('Appearance'));
        await tester.pumpAndSettle();
        await customize(tester);
        final slider = find.descendant(
          of: find.byKey(ValueKey('${scenario.$2}-${scenario.$3}')),
          matching: find.byType(Slider),
        );
        await tester.ensureVisible(slider);
        await tester.pumpAndSettle();
        await tester.tap(slider);
        await tester.pump(const Duration(milliseconds: 80));
        await tester.tap(slider);
        await tester.pumpAndSettle();
        expect(
          (c.document.appearance[scenario.$2] as Map)[scenario.$3],
          scenario.$4,
        );
        c.undo();
        expect(c.document.toJson(), original.toJson());
        expect(c.canUndo, false);
        await tester.tap(find.text('Done'));
        await tester.pumpAndSettle();
      }
    },
  );

  testWidgets(
    'plan chair distance reflows existing tables and defaults in one undo',
    (tester) async {
      final original = tableLayout(shape: 'rect', count: 6, x: 600, y: 600);
      final c = VenueLayoutController(original);
      await open(tester, c);
      await tester.tap(find.text('Appearance'));
      await tester.pumpAndSettle();
      await chairSettings(tester);
      final field = find.descendant(
        of: find.byKey(const ValueKey('plan-table-seat-gap')),
        matching: find.byType(TextField),
      );
      await tester.ensureVisible(field);
      await tester.enterText(field, '28');
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await tester.pumpAndSettle();
      expect(c.error, isNull);
      expect(documentSeating(c.document).gap, 28);
      expect(c.document.nodes.first.properties['seatGap'], 28);
      expect(
        c.document.nodes.map((n) => n.id).toSet(),
        original.nodes.map((n) => n.id).toSet(),
      );
      c.undo();
      expect(c.document.toJson(), original.toJson());
      expect(c.canUndo, false);
    },
  );

  testWidgets('wheel on global chair gap applies through validation and undo', (
    tester,
  ) async {
    final original = tableLayout(shape: 'rect', count: 4, x: 600, y: 600);
    final c = VenueLayoutController(original);
    await open(tester, c);
    await tester.tap(find.text('Appearance'));
    await tester.pumpAndSettle();
    await chairSettings(tester);
    final field = find.descendant(
      of: find.byKey(const ValueKey('plan-table-seat-gap')),
      matching: find.byType(TextField),
    );
    await tester.ensureVisible(field);
    await tester.tap(field);
    await tester.pump();
    await tester.sendEventToBinding(
      PointerScrollEvent(
        position: tester.getCenter(field),
        scrollDelta: const Offset(0, -100),
      ),
    );
    await tester.pumpAndSettle();
    expect(c.error, isNull);
    expect(documentSeating(c.document).gap, 13);
    c.undo();
    expect(c.document.toJson(), original.toJson());
    expect(c.canUndo, false);
  });

  testWidgets(
    'distinct whole-plan appearance families are primary and preserve colors and identity in one undo',
    (tester) async {
      final table = tableLayout(shape: 'roundedRect');
      final original = table.copyWith(
        appearance: {
          'table': {'fill': '#123456FF'},
          'seat': {'fill': '#AA9988FF'},
        },
      );
      final c = VenueLayoutController(original);
      await open(tester, c);
      await tester.tap(find.text('Appearance'));
      await tester.pumpAndSettle();
      expect(
        find.byKey(const ValueKey('appearance-family-simple')),
        findsNothing,
      );
      expect(
        find.byKey(const ValueKey('appearance-family-hall')),
        findsNothing,
      );
      expect(
        find.byKey(const ValueKey('appearance-family-round')),
        findsOneWidget,
      );
      expect(
        find.byKey(const ValueKey('appearance-family-wood')),
        findsOneWidget,
      );
      expect(
        find.byKey(const ValueKey('appearance-family-lounge')),
        findsOneWidget,
      );
      expect(
        find.byWidgetPredicate(
          (w) => w is TextField && w.decoration?.labelText == 'Corner radius',
        ),
        findsNothing,
      );
      final timber = find.byKey(const ValueKey('appearance-family-wood'));
      await tester.ensureVisible(timber);
      await tester.tap(timber);
      await tester.pump();
      expect((c.document.appearance['table'] as Map)['objectStyle'], 'wood');
      expect(
        (c.document.appearance['furniture'] as Map)['objectStyle'],
        'wood',
      );
      expect((c.document.appearance['seat'] as Map)['seatStyle'], 'wood');
      expect((c.document.appearance['seat'] as Map)['fill'], '#AA9988FF');
      expect((c.document.appearance['table'] as Map)['fill'], '#123456FF');
      expect(
        c.document.nodes.map((n) => n.toJson()),
        original.nodes.map((n) => n.toJson()),
      );
      expect(c.document.canvas, {...original.canvas, 'floorStyle': 'wood'});
      c.undo();
      expect(c.document.toJson(), original.toJson());
      expect(c.canUndo, false);
      // Canonical patch also supports future geometry and local exceptions.
      final styled = withAppearanceFamily(
        original,
        layoutAppearanceFamilies.firstWhere((f) => f.id == 'lounge'),
      );
      final future = LayoutNode(id: newLayoutId(), kind: 'seat');
      expect(
        effectiveNodeProperties(styled, future)['seatStyle'],
        'upholstered',
      );
      final local = future.copyWith(
        properties: {
          'objectStyle': 'simple',
          'appearanceOverrides': ['objectStyle'],
        },
      );
      expect(effectiveNodeProperties(styled, local)['objectStyle'], 'simple');
    },
  );
}
