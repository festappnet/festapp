import 'dart:async';
import 'dart:ui' show PointerDeviceKind;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:venue_seat_picker/venue_seat_picker.dart';
import 'package:venue_seat_picker/src/layout_editor/widgets/layout_scene_surface.dart';

void main() {
  testWidgets('first pointer click after hover keeps the map gesture alive', (
    tester,
  ) async {
    final id = newLayoutId();
    var calls = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: VenueLayoutPicker(
            document: VenueLayoutDocument(
              nodes: [
                LayoutNode(
                  id: id,
                  kind: 'seat',
                  x: 1200,
                  y: 800,
                  width: 100,
                  height: 100,
                ),
              ],
            ),
            showSelectionControls: false,
            seatPresentation: {
              id: {'tooltip': 'Seat A\nPrice: 100'},
            },
            onSelectionRequested: (_, _) async {
              calls++;
              return const LayoutSelectionResult(accepted: true);
            },
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    final region = find
        .descendant(
          of: find.byKey(const ValueKey('layout-map-gesture-surface')),
          matching: find.byType(MouseRegion),
        )
        .first;
    expect(tester.widget<MouseRegion>(region).cursor, SystemMouseCursors.basic);
    final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
    await mouse.addPointer(location: Offset.zero);
    await mouse.moveTo(const Offset(400, 300));
    await tester.pumpAndSettle();
    expect(find.text('Seat A\nPrice: 100'), findsOneWidget);
    expect(tester.widget<MouseRegion>(region).cursor, SystemMouseCursors.click);
    await mouse.down(const Offset(400, 300));
    await tester.pump();
    await mouse.up();
    await tester.pumpAndSettle();
    expect(calls, 1);
    await mouse.removePointer();
  });
  testWidgets(
    'host chrome hides extra footer and retains accessible list action',
    (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: VenueLayoutPicker(
              document: VenueLayoutDocument(),
              showSelectionControls: false,
              onSelectionRequested: (_, _) async =>
                  const LayoutSelectionResult(accepted: true),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('Accessible seat list'), findsNothing);
      expect(find.text('0 seats selected'), findsNothing);
      expect(find.byTooltip('Zoom in'), findsOneWidget);
      expect(find.byTooltip('Zoom out'), findsOneWidget);
      expect(find.byTooltip('Fit plan'), findsOneWidget);
      await tester.tap(find.byTooltip('Zoom in'));
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('Fit plan'));
      await tester.pumpAndSettle();
      final semantics = tester.widgetList<Semantics>(find.byType(Semantics));
      expect(
        semantics.any(
          (s) =>
              s.properties.customSemanticsActions?.keys.any(
                (a) => a.label == 'Accessible seat list',
              ) ??
              false,
        ),
        isTrue,
      );
    },
  );
  testWidgets(
    'standing restores host quantity and permits zero without a seat hold',
    (tester) async {
      final id = newLayoutId();
      final document = VenueLayoutDocument(
        nodes: [
          LayoutNode(
            id: id,
            kind: 'capacityArea',
            label: 'Standing',
            x: 100,
            y: 100,
          ),
        ],
      );
      final counts = <int>[];
      final completion = Completer<LayoutSelectionResult>();
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: VenueLayoutPicker(
              document: document,
              capacityPresentation: {
                id: {'available': 5, 'quantity': 3},
              },
              onSelectionRequested: (_, _) async =>
                  throw StateError('Standing is not a seat hold'),
              onQuantityRequested: (_, count) {
                counts.add(count);
                return completion.future;
              },
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      tester.widget<LayoutSceneSurface>(find.byType(LayoutSceneSurface)).onTap!(
        const Offset(100, 100),
      );
      await tester.pumpAndSettle();
      expect(find.text('3'), findsOneWidget);
      for (var i = 0; i < 3; i++) {
        await tester.tap(find.byTooltip('Remove one'));
        await tester.pump();
      }
      await tester.tap(find.text('Confirm quantity'));
      await tester.pump();
      expect(counts, [0]);
      completion.complete(const LayoutSelectionResult(accepted: true));
      await tester.pumpAndSettle();
      tester.widget<LayoutSceneSurface>(find.byType(LayoutSceneSurface)).onTap!(
        const Offset(100, 100),
      );
      await tester.pumpAndSettle();
      expect(find.text('0'), findsOneWidget);
      await tester.pumpWidget(const SizedBox());
      await tester.pumpAndSettle();
    },
  );
}
