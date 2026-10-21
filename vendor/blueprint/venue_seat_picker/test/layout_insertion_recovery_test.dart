import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:venue_seat_picker/venue_seat_picker.dart';
import 'package:venue_seat_picker/src/layout_editor/widgets/layout_scene_surface.dart';

void main() {
  testWidgets(
    'blocked insertion never previews the fragment origin and recovers on the same drag',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(1440, 1000));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      final source = VenueLayoutDocument(
        nodes: [
          LayoutNode(
            id: newLayoutId(),
            kind: 'table',
            x: 800,
            y: 600,
            width: 40,
            height: 40,
            surface: const {'type': 'rect'},
          ),
        ],
      );
      final c = VenueLayoutController(source);
      addTearDown(c.dispose);
      await tester.pumpWidget(
        MaterialApp(
          locale: const Locale('cs'),
          supportedLocales: VenueLayoutLocalizations.supportedLocales,
          localizationsDelegates:
              VenueLayoutLocalizations.localizationsDelegates,
          home: Scaffold(
            body: VenueLayoutEditor(controller: c, showGallery: false),
          ),
        ),
      );
      LayoutSceneSurface surface() => tester.widget<LayoutSceneSurface>(
        find.byWidgetPredicate(
          (w) => w is LayoutSceneSurface && w.onDrop != null,
        ),
      );
      surface().onDropPreview!('Table', const Offset(800, 600));
      await tester.pump();
      expect(c.error, isNull);
      expect(c.document.toJson(), source.toJson());
      surface().onDropPreview!('Table', const Offset(1600, 900));
      await tester.pump();
      expect(c.error, isNull);
      expect(c.document.nodes.where((n) => n.kind == 'seat'), hasLength(6));
      surface().onDrop!('Table', const Offset(1600, 900));
      await tester.pump();
      expect(c.gestureActive, isFalse);
      expect(c.error, isNull);
      c.undo();
      expect(c.document.toJson(), source.toJson());
      expect(c.canUndo, isFalse);
    },
  );

  testWidgets(
    'release over an obstruction cancels the insertion and leaves the next insertion usable',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(1440, 1000));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      final source = VenueLayoutDocument(
        nodes: [
          LayoutNode(
            id: newLayoutId(),
            kind: 'table',
            x: 800,
            y: 600,
            width: 600,
            height: 600,
            surface: const {'type': 'rect'},
          ),
        ],
      );
      final c = VenueLayoutController(source);
      addTearDown(c.dispose);
      await tester.pumpWidget(
        MaterialApp(
          locale: const Locale('cs'),
          supportedLocales: VenueLayoutLocalizations.supportedLocales,
          localizationsDelegates:
              VenueLayoutLocalizations.localizationsDelegates,
          home: Scaffold(
            body: VenueLayoutEditor(controller: c, showGallery: false),
          ),
        ),
      );
      LayoutSceneSurface surface() => tester.widget<LayoutSceneSurface>(
        find.byWidgetPredicate(
          (w) => w is LayoutSceneSurface && w.onDrop != null,
        ),
      );
      surface().onDropPreview!('Table', const Offset(1600, 900));
      await tester.pump();
      surface().onDropPreview!('Table', const Offset(800, 600));
      await tester.pump();
      expect(
        c.document.toJson(),
        source.toJson(),
        reason: 'No stale preview remains at the last valid point',
      );
      surface().onDrop!('Table', const Offset(800, 600));
      await tester.pump();
      expect(c.document.toJson(), source.toJson());
      expect(c.gestureActive, isFalse);
      expect(c.canUndo, isFalse);
      expect(c.error, isNot(contains('canvas')));
      expect(
        find.text('Tady není dost místa. Přesuň objekt na volnou plochu.'),
        findsOneWidget,
      );
      surface().onDrop!('Table', const Offset(1600, 900));
      await tester.pump();
      expect(c.error, isNull);
      expect(c.gestureActive, isFalse);
      expect(c.document.nodes.where((n) => n.kind == 'seat'), hasLength(6));
      expect(tester.takeException(), isNull);
    },
  );
}
