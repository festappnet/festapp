import 'package:material_ui/material_ui.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:venue_seat_picker/venue_seat_picker.dart';
import 'package:venue_seat_picker/src/layout_editor/widgets/layout_font_size_control.dart';
import 'package:venue_seat_picker/src/layout_editor/widgets/layout_inspector.dart';
import 'package:venue_seat_picker/src/layout_editor/widgets/layout_style.dart';

void main() {
  Future<VenueLayoutController> mount(
    WidgetTester tester,
    double size, {
    bool readOnly = false,
  }) async {
    final node = LayoutNode(
      surface: const {'type': 'rect'},
      id: newLayoutId(),
      kind: 'table',
      label: 'VIP',
      x: 300,
      y: 300,
      properties: {},
      style: {
        'label': {
          'size': size,
          'weight': (true == true ? 700 : 400),
          'italic': true,
        },
      },
    );
    final c = VenueLayoutController(
      VenueLayoutDocument.empty().copyWith(nodes: [node]),
    )..readOnly = readOnly;
    addTearDown(c.dispose);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SizedBox(
            width: 400,
            child: ListenableBuilder(
              listenable: c,
              builder: (_, _) => LayoutFontSizeControl(
                controller: c,
                node: c.document.nodes.single,
                value: (c.document.nodes.single.style['label']?['size'] as num)
                    .toDouble(),
              ),
            ),
          ),
        ),
      ),
    );
    return c;
  }

  testWidgets(
    'imported precise size previews continuously and commits one undo',
    (tester) async {
      final c = await mount(tester, 40.64);
      final before = c.document;
      expect(
        tester.widget<TextField>(find.byType(TextField)).controller!.text,
        '41',
      );
      final slider = find.byType(Slider);
      final gesture = await tester.startGesture(tester.getCenter(slider));
      await gesture.moveBy(const Offset(25, 0));
      await tester.pump();
      expect(c.document.nodes.single.style['label']?['size'], isNot(40.64));
      final size = c.document.nodes.single.style['label']?['size'] as num;
      expect(size, size.round());
      expect(c.canUndo, isFalse);
      await gesture.moveBy(const Offset(20, 0));
      await tester.pump();
      await gesture.up();
      await tester.pump(const Duration(milliseconds: 350));
      expect(c.canUndo, isTrue);
      expect(c.document.nodes.single.style['label']?['weight'] == 700, isTrue);
      expect(c.document.nodes.single.style['label']?['italic'], isTrue);
      expect(
        captureLayoutAppearance(
          c.document,
          c.document.nodes.single.id,
        ).object['label']['size'],
        c.document.nodes.single.style['label']?['size'],
      );
      c.undo();
      expect(c.document, same(before));
      expect(c.canUndo, isFalse);
    },
  );
  testWidgets('typed font size rounds to whole units', (tester) async {
    final c = await mount(tester, 24);
    await tester.enterText(find.byType(TextField), '32,8');
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pump();
    expect(c.document.nodes.single.style['label']?['size'], 33);
    expect(
      tester.widget<TextField>(find.byType(TextField)).controller!.text,
      '33',
    );
    c.undo();
    expect(c.document.nodes.single.style['label']?['size'], 24);
  });
  testWidgets('cancelled slider restores preview and creates no undo', (
    tester,
  ) async {
    final c = await mount(tester, 40.64), before = c.document;
    final gesture = await tester.startGesture(
      tester.getCenter(find.byType(Slider)),
    );
    await gesture.moveBy(const Offset(30, 0));
    await tester.pump();
    await gesture.cancel();
    await tester.pump(const Duration(milliseconds: 350));
    expect(c.document, same(before));
    expect(c.canUndo, isFalse);
    expect(c.gestureActive, isFalse);
  });
  testWidgets('removing the control cancels an unfinished preview', (
    tester,
  ) async {
    final c = await mount(tester, 24);
    final before = c.document;
    final gesture = await tester.startGesture(
      tester.getCenter(find.byType(Slider)),
    );
    await gesture.moveBy(const Offset(30, 0));
    await tester.pump();
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();
    expect(c.document, same(before));
    expect(c.gestureActive, isFalse);
    expect(c.canUndo, isFalse);
    await gesture.cancel();
    await tester.pump(const Duration(milliseconds: 350));
  });
  testWidgets('unchanged precise input does not round an imported size', (
    tester,
  ) async {
    final c = await mount(tester, 40.640625);
    final before = c.document;
    await tester.tap(find.byType(TextField));
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pump();
    expect(c.document, same(before));
    expect(c.canUndo, isFalse);
  });
  testWidgets(
    'large imported size remains accessible and read only disables both inputs',
    (tester) async {
      final c = await mount(tester, 512.75, readOnly: true);
      final slider = tester.widget<Slider>(find.byType(Slider));
      expect(slider.value, 512.75);
      expect(slider.max, greaterThan(512.75));
      expect(slider.onChanged, isNull);
      expect(tester.widget<TextField>(find.byType(TextField)).enabled, isFalse);
      expect(c.dirty, isFalse);
    },
  );
  testWidgets('restricted name delegates to host without geometry mutation', (
    tester,
  ) async {
    final node = LayoutNode(
      surface: const {'type': 'rect'},
      id: newLayoutId(),
      kind: 'table',
      label: 'Old',
      x: 300,
      y: 300,
    );
    final c = VenueLayoutController(
      VenueLayoutDocument.empty().copyWith(nodes: [node]),
    )..select({node.id});
    addTearDown(c.dispose);
    String? renamed;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SizedBox(
            width: 360,
            child: LayoutInspector(
              controller: c,
              cornerPivot: false,
              onPivotChanged: (_) {},
              readOnlyLabelNodeIds: {node.id},
              onRenameNode: (n, name) {
                expect(n.id, node.id);
                renamed = name;
              },
            ),
          ),
        ),
      ),
    );
    await tester.enterText(find.widgetWithText(TextField, 'Name'), 'New');
    await tester.testTextInput.receiveAction(TextInputAction.done);
    expect(renamed, 'New');
    expect(c.document.nodes.single.label, 'Old');
    expect(c.canUndo, isFalse);
  });
  test(
    'table wrapper typography copies to table labels without changing seat typography',
    () {
      final group = LayoutNode(
        id: newLayoutId(),
        kind: 'group',
        x: 300,
        y: 300,
      );
      final source = LayoutNode(
        surface: const {'type': 'rect'},
        id: newLayoutId(),
        kind: 'table',
        parentId: group.id,
        label: 'VIP',
        properties: {},
        style: {
          'label': {
            'fontFamilyId': canonicalLabelDefaults['fontFamilyId'],
            'size': 40.64,
            'weight': (true == true ? 700 : 400),
            'italic': true,
          },
        },
      );
      final target = LayoutNode(
        surface: const {'type': 'rect'},
        id: newLayoutId(),
        kind: 'table',
        label: 'Other',
        x: 700,
        y: 300,
      );
      final seat = LayoutNode(
        id: newLayoutId(),
        kind: 'seat',
        parentId: target.id,
        y: 100,
        properties: {},
        style: {
          'label': {'size': 12},
        },
      );
      final doc = VenueLayoutDocument.empty().copyWith(
        nodes: [group, source, target, seat],
      );
      final result = applyLayoutAppearance(doc, {
        target.id,
      }, captureLayoutAppearance(doc, group.id));
      final changed = result.nodes.firstWhere((n) => n.id == target.id);
      for (final key in ['fontFamilyId', 'size', 'weight', 'italic']) {
        expect(changed.style['label'][key], source.style['label'][key]);
      }
      expect(changed.label, target.label);
      expect(changed.x, target.x);
      expect(
        result.nodes.firstWhere((n) => n.id == seat.id).style['label']?['size'],
        12,
      );
      expect(result.styles, doc.styles);
      final normal = applyLayoutAppearance(doc, {
        group.id,
      }, captureLayoutAppearance(doc, target.id));
      final normalTable = normal.nodes.firstWhere((n) => n.id == source.id);
      expect(normalTable.style['label']['weight'], 400);
      expect(normalTable.style['label']?['italic'], isFalse);
      expect(
        normalTable.style['label']?['size'],
        canonicalLabelDefaults['size'],
      );
    },
  );
}
