import 'dart:convert';
import 'package:crypto/crypto.dart';
import 'package:flutter/material.dart';
import 'package:flutter/gestures.dart';
import 'package:venue_seat_picker/editor_ui.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:venue_seat_picker/venue_seat_picker.dart';
import 'package:venue_seat_picker/src/layout_editor/widgets/canonical_appearance_panel.dart';
import 'package:venue_seat_picker/src/layout_editor/widgets/layout_inspector.dart';
import 'package:venue_seat_picker/src/layout_editor/widgets/layout_style.dart';

void main() {
  testWidgets(
    'default style restores inherited rounded corners after minimal and supports undo',
    (tester) async {
      var document = tableLayout(shape: 'rect', count: 4);
      document = setKindStyleLeaf(document, 'table', [
        'cornerRadius',
      ], value: 8);
      final table = document.nodes.firstWhere((n) => n.kind == 'table');
      final c = VenueLayoutController(document);
      c.select({table.id});
      addTearDown(c.dispose);
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: AnimatedBuilder(
              animation: c,
              builder: (_, _) => LayoutInspector(
                controller: c,
                cornerPivot: false,
                onPivotChanged: (_) {},
              ),
            ),
          ),
        ),
      );
      final minimal = find.byKey(const ValueKey('layout-style-minimal'));
      await tester.ensureVisible(minimal);
      await tester.tap(minimal.hitTestable());
      await tester.pumpAndSettle();
      double radius() =>
          (resolveNodeAppearance(
                    c.document,
                    c.document.nodes.firstWhere((n) => n.id == table.id),
                  ).values['cornerRadius']
                  as num)
              .toDouble();
      expect(radius(), 3);
      final reset = find.byKey(const ValueKey('layout-style-default'));
      await tester.ensureVisible(reset);
      await tester.tap(reset.hitTestable());
      await tester.pumpAndSettle();
      expect(radius(), 8);
      final restored = c.document.nodes.firstWhere((n) => n.id == table.id);
      expect(restored.style, isEmpty);
      expect(restored.childStyles, table.childStyles);
      expect(restored.x, table.x);
      expect(restored.width, table.width);
      expect(restored.label, table.label);
      expect(
        c.document.nodes.map((n) => n.id),
        document.nodes.map((n) => n.id),
      );
      c.undo();
      expect(radius(), 3);
      c.redo();
      expect(radius(), 8);
    },
  );

  for (final hoverOnly in [true, false]) {
    testWidgets(
      'table construction keeps clicked choice and shapes chairs: hover=$hoverOnly',
      (tester) async {
        var document = tableLayout(shape: 'rect', count: 4);
        final table = document.nodes.firstWhere((n) => n.kind == 'table');
        document = setTableChildStyleLeaf(document, table.id, [
          'seatStyle',
        ], value: 'plain');
        final c = VenueLayoutController(document);
        addTearDown(c.dispose);
        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: Align(
                alignment: Alignment.centerRight,
                child: SizedBox(
                  width: 280,
                  child: SingleChildScrollView(
                    child: CanonicalAppearancePanel(
                      controller: c,
                      nodeId: table.id,
                    ),
                  ),
                ),
              ),
            ),
          ),
        );
        final button = find.widgetWithText(OutlinedButton, 'simple');
        await tester.ensureVisible(button);
        await tester.tap(button);
        await tester.pumpAndSettle();
        if (hoverOnly) {
          final mouse = await tester.createGesture(
            kind: PointerDeviceKind.mouse,
          );
          await mouse.addPointer(location: const Offset(0, 0));
          final wood = find.byWidgetPredicate(
            (w) => w is RadioListTile<String> && w.value == 'wood',
          );
          await mouse.moveTo(tester.getCenter(wood));
          await tester.pump();
          expect(c.document.toJson(), isNot(document.toJson()));
          await mouse.moveTo(const Offset(0, 0));
          await tester.pump();
          expect(
            c.document.toJson(),
            document.toJson(),
            reason: 'Leaving hover restores custom construction leaves too',
          );
          await mouse.removePointer();
        }
        final round = find.byWidgetPredicate(
          (w) => w is RadioListTile<String> && w.value == 'round',
        );
        await tester.tap(round);
        await tester.pump();
        if (hoverOnly) {
          final chosen = c.document.toJson();
          final mouse = await tester.createGesture(
            kind: PointerDeviceKind.mouse,
          );
          await mouse.addPointer(location: const Offset(0, 0));
          final wood = find.byWidgetPredicate(
            (w) => w is RadioListTile<String> && w.value == 'wood',
          );
          await mouse.moveTo(tester.getCenter(wood));
          await tester.pump();
          expect(c.document.toJson(), isNot(chosen));
          expect(
            // Retain compatibility with the declared Flutter 3.32 minimum.
            // ignore: deprecated_member_use
            tester.widget<RadioListTile<String>>(round).groupValue,
            'round',
          );
          await mouse.moveTo(const Offset(0, 0));
          await tester.pump();
          expect(c.document.toJson(), chosen);
          await mouse.removePointer();
        }
        await tester.tap(find.text('Apply'));
        await tester.pumpAndSettle();
        for (final seat in c.document.nodes.where((n) => n.kind == 'seat')) {
          expect(
            resolveNodeAppearance(c.document, seat).values['seatStyle'],
            'round',
          );
        }
        c.undo();
        expect(c.document.toJson(), document.toJson());
      },
    );
  }

  testWidgets('material chooser previews then cancels or commits once', (
    tester,
  ) async {
    final document = tableLayout(shape: 'rect', count: 0);
    final node = document.nodes.first;
    final c = VenueLayoutController(document);
    addTearDown(c.dispose);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(
            child: CanonicalAppearancePanel(controller: c, nodeId: node.id),
          ),
        ),
      ),
    );
    Future<void> chooseWood() async {
      final button = find.widgetWithText(OutlinedButton, 'simple');
      await tester.ensureVisible(button);
      await tester.tap(button);
      await tester.pumpAndSettle();
      final choice = tester.widget<RadioListTile<String>>(
        find.byWidgetPredicate(
          (w) => w is RadioListTile<String> && w.value == 'wood',
        ),
      );
      // Retain compatibility with the declared Flutter 3.32 minimum.
      // ignore: deprecated_member_use
      choice.onChanged!('wood');
      await tester.pump();
      expect(c.document.nodes.single.style['material'], 'wood');
      expect(c.canUndo, isFalse);
    }

    await chooseWood();
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    expect(c.document.toJson(), document.toJson());
    await chooseWood();
    await tester.tap(find.text('Apply'));
    await tester.pumpAndSettle();
    expect(c.document.nodes.single.style['material'], 'wood');
    c.undo();
    expect(c.document.toJson(), document.toJson());
    expect(c.canUndo, isFalse);
    expect(tester.takeException(), isNull);
  });

  testWidgets('double-click font slider restores inherited size', (
    tester,
  ) async {
    final doc = tableLayout(shape: 'rect', count: 0);
    final node = doc.nodes.first;
    final c = VenueLayoutController(
      setNodeStyleLeaf(doc, node.id, ['label', 'size'], value: 51),
    );
    addTearDown(c.dispose);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(
            child: CanonicalAppearancePanel(controller: c, nodeId: node.id),
          ),
        ),
      ),
    );
    final slider = find.byKey(const ValueKey('font-size-slider'));
    await tester.ensureVisible(slider);
    await tester.tap(slider);
    await tester.pump(const Duration(milliseconds: 50));
    await tester.tap(slider);
    await tester.pumpAndSettle();
    expect(
      (c.document.nodes.single.style['label'] as Map?)?.containsKey('size') ??
          false,
      isFalse,
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('chair size slider previews layout with one undo', (
    tester,
  ) async {
    final document = tableLayout(shape: 'rect', count: 4);
    final node = document.nodes.first;
    final c = VenueLayoutController(document)..select({node.id});
    addTearDown(c.dispose);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SizedBox(
            width: 380,
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
    final section = find.text('Chair layout');
    await tester.ensureVisible(section);
    await tester.tap(section);
    await tester.pumpAndSettle();
    final slider = tester.widget<Slider>(
      find.byKey(const ValueKey('number-slider:Chair width')),
    );
    slider.onChangeStart!(40);
    slider.onChanged!(50);
    slider.onChanged!(60);
    slider.onChangeEnd!(60);
    await tester.pumpAndSettle();
    expect(
      TableSeating.fromDocument(
        c.document,
        c.document.nodes.firstWhere((n) => n.id == node.id),
      ).width,
      60,
    );
    expect(
      c.document.nodes.map((n) => n.id).toSet(),
      document.nodes.map((n) => n.id).toSet(),
    );
    c.undo();
    expect(c.document.toJson(), document.toJson());
    expect(c.canUndo, isFalse);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'saved style is offered immediately and can be renamed, removed and restored',
    (tester) async {
      final document = tableLayout(shape: 'rect', count: 2);
      final c = VenueLayoutController(document)
        ..select({document.nodes.first.id});
      addTearDown(c.dispose);
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SizedBox(
              width: 380,
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
      final more = find.byTooltip('Style actions');
      await tester.ensureVisible(more);
      await tester.tap(more);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Save as style'));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.widgetWithText(TextFormField, 'Style name'),
        'VIP',
      );
      await tester.tap(find.widgetWithText(FilledButton, 'Save'));
      await tester.pumpAndSettle();
      expect(c.document.presets.single['title'], 'VIP');
      final id = c.document.presets.single['id'] as String;
      expect(find.byKey(ValueKey('layout-style-$id')), findsOneWidget);
      await tester.ensureVisible(more);
      await tester.tap(more);
      await tester.pumpAndSettle();
      await tester.tap(find.text('My styles'));
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('Rename style'));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.widgetWithText(TextFormField, 'Style name'),
        'Lóže',
      );
      await tester.tap(find.widgetWithText(FilledButton, 'Save'));
      await tester.pumpAndSettle();
      expect(c.document.presets.single['title'], 'Lóže');
      await tester.tap(find.byTooltip('Delete style'));
      await tester.pumpAndSettle();
      expect(c.document.presets, isEmpty);
      c.undo();
      expect(c.document.presets.single['title'], 'Lóže');
      expect(
        c.document.nodes.map((n) => n.toJson()),
        document.nodes.map((n) => n.toJson()),
      );
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('font slider updates canonical scope in one reversible gesture', (
    tester,
  ) async {
    final c = VenueLayoutController(VenueLayoutDocument.empty());
    addTearDown(c.dispose);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(
            child: CanonicalAppearancePanel(controller: c, global: true),
          ),
        ),
      ),
    );
    final slider = tester.widget<Slider>(
      find.byKey(const ValueKey('font-size-slider')),
    );
    slider.onChangeStart!(24);
    slider.onChanged!(32);
    slider.onChanged!(51);
    slider.onChangeEnd!(51);
    await tester.pumpAndSettle();
    expect(c.document.styles['label']['size'], 51);
    c.undo();
    expect(c.document.styles['label'], isNull);
    expect(c.canUndo, isFalse);
    c.redo();
    expect(c.document.styles['label']['size'], 51);
  });

  test(
    'named appearance survives document roundtrip and applies without geometry changes',
    () {
      final base = tableLayout(shape: 'rect', count: 3);
      final root = base.nodes.first;
      final styled = setNodeStyleLeaf(base, root.id, [
        'fill',
      ], value: '#112233FF');
      final saved = saveLayoutAppearancePreset(
        styled,
        styled.nodes.first,
        'Můj styl',
      );
      expect(validateDocument(saved), isEmpty);
      final restored = VenueLayoutDocument.fromJson(saved.toJson());
      expect(restored.presets.single['title'], 'Můj styl');
      final appearance = namedLayoutAppearances(
        restored,
        'table',
      ).values.single;
      expect(appearance.object['fill'], '#112233FF');
      final applied = applyLayoutAppearance(restored, {root.id}, appearance);
      for (var i = 0; i < applied.nodes.length; i++) {
        final before = base.nodes.firstWhere(
          (n) => n.id == applied.nodes[i].id,
        );
        expect(applied.nodes[i].id, before.id);
        expect(applied.nodes[i].x, before.x);
        expect(applied.nodes[i].y, before.y);
        expect(applied.nodes[i].width, before.width);
        expect(applied.nodes[i].height, before.height);
        expect(applied.nodes[i].label, before.label);
      }
      expect(
        () => saveLayoutAppearancePreset(saved, saved.nodes.first, 'můj styl'),
        throwsFormatException,
      );
    },
  );

  testWidgets('style target stays separated from the floating font label', (
    tester,
  ) async {
    final c = VenueLayoutController(VenueLayoutDocument.empty());
    addTearDown(c.dispose);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(
            child: CanonicalAppearancePanel(
              controller: c,
              global: true,
              globalFontPickerBuilder: (_, _) => const TextField(
                key: ValueKey('font-picker'),
                decoration: InputDecoration(
                  labelText: 'Typography',
                  border: OutlineInputBorder(),
                ),
              ),
            ),
          ),
        ),
      ),
    );
    final target = find.byKey(const ValueKey('canonical-style-target'));
    final font = find.byKey(const ValueKey('font-picker'));
    expect(
      tester.getTopLeft(font).dy - tester.getBottomLeft(target).dy,
      greaterThanOrEqualTo(24),
    );
    final dropdown = tester.widget<DropdownButtonFormField<String>>(target);
    dropdown.onChanged!('table');
    await tester.pump();
    expect(find.byKey(const ValueKey('canonical-style-fill')), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'table essentials precede appearance and geometry is expandable',
    (tester) async {
      final d = tableLayout(shape: 'rect', count: 2);
      final node = d.nodes.first;
      final c = VenueLayoutController(d)..select({node.id});
      addTearDown(c.dispose);
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SizedBox(
              width: 380,
              child: LayoutInspector(
                controller: c,
                cornerPivot: false,
                onPivotChanged: (_) {},
              ),
            ),
          ),
        ),
      );
      final name = find.widgetWithText(TextField, 'Name');
      final shape = find.byWidgetPredicate(
        (w) =>
            w is DropdownButtonFormField<String> &&
            w.decoration.labelText == 'Table shape',
      );
      final seats = find.widgetWithText(TextField, 'Seats');
      final fill = find.byKey(const ValueKey('canonical-style-fill'));
      expect(tester.getTopLeft(name).dy, lessThan(tester.getTopLeft(shape).dy));
      expect(
        tester.getTopLeft(shape).dy,
        lessThan(tester.getTopLeft(seats).dy),
      );
      expect(tester.getTopLeft(seats).dy, lessThan(tester.getTopLeft(fill).dy));
      expect(find.widgetWithText(TextField, 'Chair width'), findsNothing);
      expect(find.widgetWithText(TextField, 'X'), findsNothing);
      final geometry = find.text('Position and size');
      await tester.ensureVisible(geometry);
      await tester.tap(geometry);
      await tester.pumpAndSettle();
      expect(find.widgetWithText(TextField, 'X'), findsOneWidget);
      expect(c.document.toJson(), d.toJson());
      expect(c.canUndo, isFalse);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'image object crop validates a preview and commits one reversible edit without changing seats',
    (tester) async {
      final image = LayoutNode(
            id: newLayoutId(),
            kind: 'image',
            x: 200,
            y: 200,
            width: 180,
            height: 100,
            graphic: {
              'type': 'bitmap',
              'assetRef': 'image:fixture',
              'hash': 'a' * 64,
              'crop': {'x': 0, 'y': 0, 'width': 1, 'height': 1},
            },
          ),
          seat = LayoutNode(id: newLayoutId(), kind: 'seat', x: 500, y: 400);
      final original = VenueLayoutDocument(
            schemaVersion: 2,
            nodes: [image, seat],
          ),
          c = VenueLayoutController(original)..select({image.id});
      addTearDown(c.dispose);
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SizedBox(
              width: 400,
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
      final crop = find.text('Crop image');
      await tester.ensureVisible(crop);
      await tester.tap(crop);
      await tester.pumpAndSettle();
      final fields = find.descendant(
        of: find.byType(AlertDialog),
        matching: find.byType(TextFormField),
      );
      expect(fields, findsNWidgets(4));
      await tester.enterText(fields.at(2), '1.2');
      await tester.pump();
      expect(
        tester
            .widget<FilledButton>(
              find.descendant(
                of: find.byType(AlertDialog),
                matching: find.byType(FilledButton),
              ),
            )
            .onPressed,
        isNull,
      );
      expect(c.document.nodes.first.graphic!['crop']['width'], 1);
      await tester.enterText(fields.at(2), '0.5');
      await tester.pump();
      expect(c.document.nodes.first.graphic!['crop']['width'], 0.5);
      expect(c.document.nodes.last.toJson(), seat.toJson());
      await tester.tap(
        find.descendant(
          of: find.byType(AlertDialog),
          matching: find.byType(FilledButton),
        ),
      );
      await tester.pumpAndSettle();
      expect(c.canUndo, isTrue);
      c.undo();
      expect(c.document.toJson(), original.toJson());
      expect(c.canUndo, isFalse);
      c.redo();
      expect(c.document.nodes.first.graphic!['crop']['width'], 0.5);
    },
  );

  testWidgets('document controls resolve their own scope and reset one leaf', (
    tester,
  ) async {
    final c = VenueLayoutController(
      VenueLayoutDocument(
        schemaVersion: 2,
        styles: {
          'label': {'size': 28, 'color': '#112233FF'},
          'kinds': {
            'text': {
              'label': {'size': 80},
            },
          },
        },
      ),
    );
    addTearDown(c.dispose);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(
            child: CanonicalAppearancePanel(controller: c, global: true),
          ),
        ),
      ),
    );
    expect(find.widgetWithText(TextField, '28'), findsOneWidget);
    expect(find.widgetWithText(TextField, '80.0'), findsNothing);
    final reset = find.byWidgetPredicate(
      (widget) =>
          widget is IconButton && widget.tooltip == 'Reset to inherited value',
    );
    final enabled = tester
        .widgetList<IconButton>(reset)
        .where((button) => button.onPressed != null)
        .toList();
    expect(enabled, hasLength(2));
    enabled.first.onPressed!();
    await tester.pump();
    expect(c.document.styles['label'], {'color': '#112233FF'});
    expect(c.document.styles['kinds']['text']['label']['size'], 80);
    expect(find.widgetWithText(TextField, '24'), findsOneWidget);
    c.undo();
    expect(c.document.styles['label']['size'], 28);
  });
  testWidgets(
    'face switches require the actual target face including switching off',
    (tester) async {
      final payload = {
        'family': 'Bold only',
        'version': 1,
        'faces': {'700:normal': 'font:bold'},
      };
      final hash = sha256
              .convert(utf8.encode(canonicalContractJson(payload)))
              .toString(),
          id =
              'font-family:${sha256.convert(utf8.encode(canonicalContractJson(payload)))}';
      final node = LayoutNode(
        id: newLayoutId(),
        kind: 'text',
        x: 400,
        y: 400,
        width: 100,
        height: 100,
        properties: {'text': 'AV'},
        style: {
          'label': {'weight': 700},
        },
      );
      final c = VenueLayoutController(
        VenueLayoutDocument(
          schemaVersion: 2,
          styles: {
            'label': {'fontFamilyId': id},
          },
          nodes: [node],
        ),
        resources: {
          'protocol': 2,
          'fontFamilies': {
            id: {...payload, 'id': id, 'hash': hash},
          },
          'textLayouts': {},
        },
      );
      addTearDown(c.dispose);
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SingleChildScrollView(
              child: CanonicalAppearancePanel(controller: c, nodeId: node.id),
            ),
          ),
        ),
      );
      final buttons = tester.widget<EditorTextStyleControl>(
        find.byKey(const ValueKey('canonical-font-style')),
      );
      expect(buttons.selected, {'bold'});
      expect(buttons.available.isEmpty, isTrue);
      expect(c.document.nodes.single.style['label']['weight'], 700);
    },
  );
}
