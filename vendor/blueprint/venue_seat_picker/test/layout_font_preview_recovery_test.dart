import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:venue_seat_picker/venue_seat_picker.dart';
import 'package:venue_seat_picker/editor_ui.dart';
import 'package:venue_seat_picker/src/layout_editor/widgets/canonical_appearance_panel.dart';
import 'package:venue_seat_picker/src/layout_editor/widgets/layout_scene_surface.dart';
import 'package:venue_seat_picker/src/layout_editor/widgets/layout_palette_thumbnail.dart';

void main() {
  const oldFamily = '10000000-0000-4000-8000-000000000001';
  const nextFamily = '10000000-0000-4000-8000-000000000002';
  final text = LayoutNode(
    id: newLayoutId(),
    kind: 'text',
    x: 100,
    y: 100,
    properties: const {'text': 'Font test'},
  );
  VenueLayoutDocument doc(String family) => VenueLayoutDocument(
    nodes: [
      text.copyWith(
        style: {
          'label': {'fontFamilyId': family},
        },
      ),
    ],
  );
  Future<void> open(
    WidgetTester t,
    String family,
    Future<TextStyle> Function(LayoutNode) load,
  ) => t.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: LayoutSceneSurface(
          key: const ValueKey('preview'),
          document: doc(family),
          retainPendingTextPreview: true,
          inlineTextStyleBuilder: load,
        ),
      ),
    ),
  );

  testWidgets('failed old font is cleared when switching to a ready font', (
    t,
  ) async {
    Future<TextStyle> load(LayoutNode n) async {
      if ((n.style['label'] as Map)['fontFamilyId'] == oldFamily) {
        throw StateError('temporary_failure');
      }
      return const TextStyle(fontFamily: 'Ahem');
    }

    await open(t, oldFamily, load);
    await t.pumpAndSettle();
    await open(t, nextFamily, load);
    await t.pumpAndSettle();
    expect(find.text('Part of the plan could not be displayed.'), findsNothing);
    expect(find.text('The selected font could not be loaded.'), findsNothing);
  });
  testWidgets(
    'late failure of a previous font cannot mark the current font broken',
    (t) async {
      final late = Completer<TextStyle>();
      Future<TextStyle> load(LayoutNode n) =>
          (n.style['label'] as Map)['fontFamilyId'] == oldFamily
          ? late.future
          : Future.value(const TextStyle(fontFamily: 'Ahem'));
      await open(t, oldFamily, load);
      await t.pump();
      await open(t, nextFamily, load);
      await t.pumpAndSettle();
      late.completeError(StateError('late_failure'));
      await t.pumpAndSettle();
      expect(
        find.text('Part of the plan could not be displayed.'),
        findsNothing,
      );
      expect(find.text('The selected font could not be loaded.'), findsNothing);
    },
  );
  testWidgets(
    'a failed active font offers a retry and reloads its actual face',
    (t) async {
      var attempts = 0;
      Future<TextStyle> load(LayoutNode n) async {
        if (++attempts == 1) throw StateError('temporary_failure');
        return const TextStyle(fontFamily: 'Ahem');
      }

      await open(t, oldFamily, load);
      await t.pumpAndSettle();
      expect(
        find.text('The selected font could not be loaded.'),
        findsOneWidget,
      );
      await t.tap(find.text('Retry font'));
      await t.pumpAndSettle();
      expect(attempts, 2);
      expect(find.text('The selected font could not be loaded.'), findsNothing);
    },
  );
  testWidgets(
    'text tool schematic stays visible in both themes without prepared text',
    (t) async {
      for (final brightness in Brightness.values) {
        await t.pumpWidget(
          MaterialApp(
            theme: ThemeData(brightness: brightness),
            home: Scaffold(
              body: LayoutPaletteThumbnail(
                document: doc(oldFamily),
                resources: const {},
                kind: 'Text',
              ),
            ),
          ),
        );
        await t.pumpAndSettle();
        expect(find.text('Aa'), findsOneWidget);
        final label = t.widget<Text>(find.text('Aa'));
        final theme = Theme.of(t.element(find.text('Aa')));
        expect(label.style!.color, theme.colorScheme.onSurface);
      }
    },
  );
  testWidgets(
    'font style buttons disable unavailable bold while retaining supported italic',
    (t) async {
      final fixture =
          jsonDecode(
                File(
                  'web/test/fixtures/canonical_rendering.json',
                ).readAsStringSync(),
              )
              as Map;
      final resources = Map<String, dynamic>.from(fixture['resources']);
      final families = resources['fontFamilies'] as Map;
      final family = families.entries.firstWhere(
        (e) => !(e.value['faces'] as Map).containsKey('700:normal'),
      );
      final node = text.copyWith(
        style: {
          'label': {'fontFamilyId': family.key, 'weight': 400, 'italic': false},
        },
      );
      final c = VenueLayoutController(
        VenueLayoutDocument(nodes: [node]),
        resources: resources,
      );
      addTearDown(c.dispose);
      await t.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SingleChildScrollView(
              child: CanonicalAppearancePanel(controller: c, nodeId: node.id),
            ),
          ),
        ),
      );
      await t.pumpAndSettle();
      final control = t.widget<EditorTextStyleControl>(
        find.byKey(const ValueKey('canonical-font-style')),
      );
      expect(control.available, {'italic'});
      expect(control.selected, isEmpty);
      final buttons = t.widget<SegmentedButton<String>>(
        find.descendant(
          of: find.byKey(const ValueKey('canonical-font-style')),
          matching: find.byType(SegmentedButton<String>),
        ),
      );
      expect(
        buttons.segments.firstWhere((s) => s.value == 'bold').enabled,
        false,
      );
      expect(
        buttons.segments.firstWhere((s) => s.value == 'italic').enabled,
        true,
      );
      control.onChanged!({'italic'});
      await t.pumpAndSettle();
      expect(
        resolveNodeAppearance(
          c.document,
          c.document.nodes.single,
        ).label['weight'],
        400,
      );
      expect(
        resolveNodeAppearance(
          c.document,
          c.document.nodes.single,
        ).label['italic'],
        true,
      );
    },
  );
}
