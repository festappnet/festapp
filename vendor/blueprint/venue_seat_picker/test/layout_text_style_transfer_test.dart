import 'package:material_ui/material_ui.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:venue_seat_picker/venue_seat_picker.dart';
import 'package:venue_seat_picker/src/layout_editor/widgets/canonical_appearance_panel.dart';
import 'package:venue_seat_picker/src/layout_editor/widgets/layout_style.dart';

VenueLayoutDocument fixture() => VenueLayoutDocument(
  styles: {
    'label': {'size': 20},
  },
  nodes: [
    LayoutNode(
      id: '00000000-0000-4000-8000-000000000001',
      kind: 'table',
      label: 'VIP',
      x: 100,
      surface: {'type': 'rect'},
      style: {
        'fill': '#112233FF',
        'label': {
          'size': 60,
          'weight': 700,
          'italic': true,
          'color': '#AA2200FF',
          'align': 'right',
        },
      },
    ),
    LayoutNode(
      id: '00000000-0000-4000-8000-000000000002',
      kind: 'table',
      label: 'Stůl 2',
      x: 400,
      surface: {'type': 'circle'},
      style: {
        'fill': '#FFEEDDFF',
        'label': {'size': 18, 'weight': 400, 'align': 'left'},
      },
    ),
    LayoutNode(
      id: '00000000-0000-4000-8000-000000000003',
      kind: 'table',
      label: 'Locked',
      x: 700,
      locked: true,
      surface: {'type': 'rect'},
    ),
    LayoutNode(id: '00000000-0000-4000-8000-000000000004', kind: 'seat', parentId: '00000000-0000-4000-8000-000000000001', x: 50, y: 80),
    LayoutNode(id: '00000000-0000-4000-8000-000000000005', kind: 'text', properties: {'text': 'Heading'}),
  ],
);

void main() {
  test(
    'text transfer replaces peer typography only and preserves locked objects and identities',
    () {
      final doc = fixture(), source = fixture().nodes.first;
      final result = applyLayoutTextStyle(doc, source);
      expect(layoutTextStyleTargets(doc, source), {'00000000-0000-4000-8000-000000000002'});
      expect(
        resolveNodeAppearance(result, result.nodes[1]).label,
        resolveNodeAppearance(doc, source).label,
      );
      expect(result.styles, doc.styles);
      for (var i = 0; i < doc.nodes.length; i++) {
        if (i != 1) {
          expect(result.nodes[i].toJson(), doc.nodes[i].toJson());
        } else {
          expect(
            result.nodes[i].copyWith(style: doc.nodes[i].style).toJson(),
            doc.nodes[i].toJson(),
          );
          expect(result.nodes[i].style['fill'], '#FFEEDDFF');
        }
      }
      final c = VenueLayoutController(doc);
      addTearDown(c.dispose);
      expect(c.apply(result), isTrue);
      c.undo();
      expect(c.document.toJson(), doc.toJson());
      c.redo();
      expect(c.document.toJson(), result.toJson());
    },
  );

  testWidgets('text section offers counted contextual transfer and one undo', (
    tester,
  ) async {
    final c = VenueLayoutController(fixture());
    addTearDown(c.dispose);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(
            child: CanonicalAppearancePanel(controller: c, nodeId: '00000000-0000-4000-8000-000000000001'),
          ),
        ),
      ),
    );
    final action = find.byKey(const ValueKey('apply-text-style-to-peers'));
    await tester.ensureVisible(action);
    await tester.pumpAndSettle();
    expect(find.text('Apply text to other tables (1)'), findsOneWidget);
    await tester.tap(action);
    await tester.pumpAndSettle();
    expect(
      resolveNodeAppearance(c.document, c.document.nodes[1]).label['size'],
      60,
    );
    await tester.tap(find.text('Undo'));
    await tester.pumpAndSettle();
    expect(
      resolveNodeAppearance(c.document, c.document.nodes[1]).label['size'],
      18,
    );
  });
}
