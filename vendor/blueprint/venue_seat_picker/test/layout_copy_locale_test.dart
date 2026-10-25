import 'package:material_ui/material_ui.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:venue_seat_picker/venue_seat_picker.dart';
import 'package:venue_seat_picker/src/layout_editor/widgets/layout_scene_surface.dart';

void main() {
  test(
    'insert and duplicate allocate consecutive localized table names, keeping custom names',
    () {
      final original = VenueLayoutTemplates.create(
        'ball-classic',
        localize: const VenueLayoutLocalizations(Locale('cs')).text,
      );
      final c = VenueLayoutController(original, tableLabelPrefix: 'Stůl');
      addTearDown(c.dispose);
      final table = original.nodes.firstWhere((n) => n.label == 'Stůl 1');
      c.select({table.id});
      c.duplicateSelection();
      expect(
        c.document.nodes.firstWhere((n) => c.selection.contains(n.id)).label,
        'Stůl 13',
      );
      c.duplicateSelection();
      expect(
        c.document.nodes.firstWhere((n) => c.selection.contains(n.id)).label,
        'Stůl 14',
      );
      final custom = c.document.nodes.firstWhere(
        (n) => c.selection.contains(n.id),
      );
      c.updateNode(custom.copyWith(label: 'VIP'));
      c.duplicateSelection();
      expect(
        c.document.nodes.firstWhere((n) => c.selection.contains(n.id)).label,
        'VIP 2',
      );
      expect(
        c.document.nodes.firstWhere((n) => n.id == custom.id).label,
        'VIP',
      );
      expect(validateDocument(c.document), isEmpty);
    },
  );

  test(
    'table numbers follow spatial order rather than fragment array/UUID order',
    () {
      final c = VenueLayoutController(VenueLayoutDocument.empty());
      addTearDown(c.dispose);
      final left = LayoutNode(id: newLayoutId(), kind: 'table', x: 100, y: 100);
      final right = LayoutNode(
        id: newLayoutId(),
        kind: 'table',
        x: 300,
        y: 100,
      );
      final named = c.nameInsertedTables(
        VenueLayoutDocument(nodes: [right, left]),
      );
      expect(named.nodes.firstWhere((n) => n.id == left.id).label, 'Table 1');
      expect(named.nodes.firstWhere((n) => n.id == right.id).label, 'Table 2');
    },
  );

  test(
    'package defaults translate node text and titles without translating identities or custom labels',
    () {
      const cs = VenueLayoutLocalizations(Locale('cs'));
      final doc = VenueLayoutTemplates.create('ball-balcony');
      final custom = LayoutNode(
        id: newLayoutId(),
        kind: 'text',
        label: 'My custom room',
        properties: {'text': 'My custom room'},
      );
      final translated = localizeLayoutDefaultLabels(
        doc.copyWith(nodes: [...doc.nodes, custom]),
        cs.text,
      );
      expect(
        translated.nodes.map((n) => n.id),
        [...doc.nodes, custom].map((n) => n.id),
      );
      expect(
        translated.sections.map((s) => s['levelId']),
        doc.sections.map((s) => s['levelId']),
      );
      expect(translated.sections.first['title'], 'Přízemí');
      expect(
        translated.nodes.where(
          (n) => n.kind == 'text' && n.properties['text'] == 'Přízemí',
        ),
        isNotEmpty,
      );
      expect(translated.nodes.last.label, custom.label);
      expect(translated.nodes.any((n) => n.label == 'Column'), false);
      expect(
        const VenueLayoutLocalizations(Locale('en')).tableName(2),
        'Table 2',
      );
      expect(cs.tableName(2), 'Stůl 2');
      expect(
        const VenueLayoutLocalizations(Locale('fr')).text('Properties'),
        'Properties',
      );
      expect(validateDocument(translated), isEmpty);
    },
  );

  testWidgets(
    'Flutter locale delegate switches package language; host resolver can override',
    (tester) async {
      Widget app(Locale locale) => MaterialApp(
        locale: locale,
        supportedLocales: VenueLayoutLocalizations.supportedLocales,
        localizationsDelegates: VenueLayoutLocalizations.localizationsDelegates,
        home: const Scaffold(body: LayoutText('Properties')),
      );
      await tester.pumpWidget(app(const Locale('cs')));
      await tester.pumpAndSettle();
      expect(find.text('Vlastnosti'), findsOneWidget);
      await tester.pumpWidget(app(const Locale('en')));
      await tester.pumpAndSettle();
      expect(find.text('Properties'), findsOneWidget);
      await tester.pumpWidget(
        MaterialApp(
          home: VenueLayoutStrings(
            resolve: (_) => 'Host term',
            child: const Scaffold(body: LayoutText('Properties')),
          ),
        ),
      );
      expect(find.text('Host term'), findsOneWidget);
    },
  );

  testWidgets('real pointer copy survives blocked-to-valid movement', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(1440, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final original = tableLayout(shape: 'rect', x: 600, y: 600, count: 6);
    final c = VenueLayoutController(original);
    addTearDown(c.dispose);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: VenueLayoutEditor(controller: c, showGallery: false),
        ),
      ),
    );
    await tester.pumpAndSettle();
    final finder = find.byType(LayoutSceneSurface);
    final rect = tester.getRect(finder), canvas = original.canvas;
    final w = (canvas['width'] as num).toDouble(),
        h = (canvas['height'] as num).toDouble();
    final sx = (rect.width - 32) / w, sy = (rect.height - 32) / h;
    final scale = sx < sy ? sx : sy;
    Offset at(double x, double y) =>
        rect.topLeft +
        Offset(
          (rect.width - w * scale) / 2 + x * scale,
          (rect.height - h * scale) / 2 + y * scale,
        );
    await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
    final drag = await tester.startGesture(at(600, 600));
    await drag.moveTo(at(680, 600));
    await tester.pump();
    expect(c.document.nodes, hasLength(14));
    FocusManager.instance.primaryFocus?.unfocus();
    await tester.pump();
    expect(
      c.document.nodes,
      hasLength(14),
      reason: 'Keyboard focus changes must not cancel a live pointer copy',
    );
    await drag.moveTo(at(1100, 900));
    await tester.pump();
    expect(c.document.nodes, hasLength(14));
    expect(
      tester.widget<LayoutSceneSurface>(finder).blockedPlacementHulls,
      isEmpty,
    );
    await drag.up();
    await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
    await tester.pump();
    expect(c.document.nodes, hasLength(14));
    await tester.pump(const Duration(milliseconds: 350));
  });

  for (final modifier in [
    LogicalKeyboardKey.controlLeft,
    LogicalKeyboardKey.metaLeft,
  ]) {
    testWidgets('modifier drag clones assembly atomically: $modifier', (
      tester,
    ) async {
      await tester.binding.setSurfaceSize(const Size(1440, 900));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      final original = tableLayout(shape: 'roundedRect', count: 6);
      final c = VenueLayoutController(original);
      addTearDown(c.dispose);
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: VenueLayoutEditor(controller: c, showGallery: false),
          ),
        ),
      );
      final finder = find.byWidgetPredicate(
        (w) => w is LayoutSceneSurface && w.onViewportScaleChanged != null,
      );
      LayoutSceneSurface surface() => tester.widget<LayoutSceneSurface>(finder);
      final table = original.nodes.firstWhere((n) => n.kind == 'table');
      await tester.sendKeyDownEvent(modifier);
      surface().onDragStart!(Offset(table.x, table.y));
      final copyId = c.selection.single;
      // The copied origin overlaps its source: preview the blocked location,
      // then move clear without releasing the modifier or pointer.
      surface().onDragUpdate!(Offset(table.x + 40, table.y));
      await tester.pump();
      expect(surface().blockedPlacementHulls, isNotEmpty);
      surface().onDragUpdate!(Offset(table.x + 500, table.y + 300));
      await tester.pump();
      expect(surface().blockedPlacementHulls, isEmpty);
      expect(c.document.nodes.any((node) => node.id == copyId), isTrue);
      expect(c.selection, {copyId});
      surface().onDragUpdate!(Offset(table.x + 500, table.y + 300));
      surface().onDragEnd!();
      await tester.sendKeyUpEvent(modifier);
      expect(c.document.nodes, hasLength(14));
      final copy = c.selection.single;
      expect(copy, isNot(table.id));
      expect(c.document.nodes.where((n) => n.parentId == copy), hasLength(6));
      expect(
        c.document.nodes.firstWhere((n) => n.id == table.id).toJson(),
        table.toJson(),
      );
      c.undo();
      expect(c.document.toJson(), original.toJson());
      expect(c.canUndo, false);
      await tester.pump();
      await tester.sendKeyDownEvent(modifier);
      surface().onDragStart!(Offset(table.x, table.y));
      surface().onDragUpdate!(Offset(table.x + 80, table.y));
      surface().onDragCancel!();
      await tester.sendKeyUpEvent(modifier);
      expect(c.document.toJson(), original.toJson());
    });
  }
}
