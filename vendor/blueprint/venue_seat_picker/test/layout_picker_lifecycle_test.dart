import 'dart:async';
import 'package:material_ui/material_ui.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:venue_seat_picker/venue_seat_picker.dart';
import 'package:venue_seat_picker/src/layout_editor/widgets/layout_scene_surface.dart';

void main() {
  testWidgets(
    'preselected seat releases visibly and rejection restores it; pending ignores repeats',
    (tester) async {
      final id = newLayoutId(),
          doc = VenueLayoutDocument(
            nodes: [
              LayoutNode(id: newLayoutId(), kind: 'shape', width: 1, height: 1),
              LayoutNode(id: id, kind: 'seat', x: 100, y: 100),
            ],
          );
      final result = Completer<LayoutSelectionResult>();
      var calls = 0;
      bool? selecting;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: VenueLayoutPicker(
              document: doc,
              seatPresentation: {
                id: {'selected': true},
              },
              onSelectionRequested: (ids, value) {
                calls++;
                selecting = value;
                return result.future;
              },
            ),
          ),
        ),
      );
      expect(find.text('1 seats selected'), findsOneWidget);
      final surface = tester.widget<LayoutSceneSurface>(
        find.byType(LayoutSceneSurface),
      );
      surface.onTap!(const Offset(100, 100));
      await tester.pump();
      expect(selecting, false);
      expect(calls, 1);
      expect(
        tester
            .widget<LayoutSceneSurface>(find.byType(LayoutSceneSurface))
            .presentation[id]['selected'],
        false,
      );
      surface.onTap!(const Offset(100, 100));
      expect(calls, 1);
      result.complete(const LayoutSelectionResult(accepted: false));
      await tester.pumpAndSettle();
      expect(find.text('1 seats selected'), findsOneWidget);
      expect(
        tester
            .widget<LayoutSceneSurface>(find.byType(LayoutSceneSurface))
            .presentation[id]['selected'],
        true,
      );
    },
  );

  testWidgets('authority recovery wins over optimistic rollback', (
    tester,
  ) async {
    final id = newLayoutId();
    final doc = VenueLayoutDocument(
      nodes: [LayoutNode(id: id, kind: 'seat', x: 100, y: 100)],
    );
    final response = Completer<LayoutSelectionResult>();
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: VenueLayoutPicker(
            document: doc,
            onSelectionRequested: (_, _) => response.future,
          ),
        ),
      ),
    );
    tester.widget<LayoutSceneSurface>(find.byType(LayoutSceneSurface)).onTap!(
      const Offset(100, 100),
    );
    await tester.pump();
    response.complete(
      LayoutSelectionResult(accepted: false, authoritativeSeatIds: {id}),
    );
    await tester.pumpAndSettle();
    expect(
      tester
          .widget<LayoutSceneSurface>(find.byType(LayoutSceneSurface))
          .presentation[id]['selected'],
      true,
    );
  });

  final seatId = newLayoutId(), areaId = newLayoutId();
  VenueLayoutDocument document() => VenueLayoutDocument.empty().copyWith(
    nodes: [
      LayoutNode(id: seatId, kind: 'seat', x: 100, y: 100),
      LayoutNode(
        id: areaId,
        kind: 'capacityArea',
        x: 400,
        y: 300,
        width: 100,
        height: 100,
        properties: const {'capacity': 20},
      ),
    ],
  );
  void choose(WidgetTester tester, Offset point) => tester
      .widget<LayoutSceneSurface>(find.byType(LayoutSceneSurface))
      .onTap!(point);

  testWidgets(
    'replacement fences old seat completion and preserves new pending request',
    (tester) async {
      final old = Completer<LayoutSelectionResult>(),
          next = Completer<LayoutSelectionResult>();
      var doc = document();
      var callback = (Set<String> ids, bool selecting) => old.future;
      late StateSetter update;
      await tester.pumpWidget(
        MaterialApp(
          home: StatefulBuilder(
            builder: (context, set) {
              update = set;
              return Scaffold(
                body: VenueLayoutPicker(
                  document: doc,
                  onSelectionRequested: callback,
                ),
              );
            },
          ),
        ),
      );
      choose(tester, const Offset(100, 100));
      await tester.pump();
      expect(find.text('1 seats selected'), findsOneWidget);
      update(() {
        doc = document();
        callback = (ids, selecting) => next.future;
      });
      await tester.pump();
      expect(find.text('0 seats selected'), findsOneWidget);
      expect(find.byType(LinearProgressIndicator), findsNothing);
      choose(tester, const Offset(100, 100));
      await tester.pump();
      old.complete(
        const LayoutSelectionResult(accepted: false, message: 'stale seat'),
      );
      await tester.pump();
      expect(find.byType(LinearProgressIndicator), findsOneWidget);
      expect(find.text('stale seat'), findsNothing);
      expect(find.text('1 seats selected'), findsOneWidget);
      next.complete(const LayoutSelectionResult(accepted: true));
      await tester.pumpAndSettle();
      expect(find.text('1 seats selected'), findsOneWidget);
      expect(find.byType(LinearProgressIndicator), findsNothing);
    },
  );

  testWidgets(
    'presentation changes preserve selection and sold or blocked seats never dispatch',
    (tester) async {
      final doc = document();
      var status = 'available', calls = 0;
      late StateSetter update;
      await tester.pumpWidget(
        MaterialApp(
          home: StatefulBuilder(
            builder: (context, set) {
              update = set;
              return Scaffold(
                body: VenueLayoutPicker(
                  document: doc,
                  seatPresentation: {
                    seatId: {'status': status},
                  },
                  onSelectionRequested: (ids, selecting) async {
                    calls++;
                    return const LayoutSelectionResult(accepted: true);
                  },
                ),
              );
            },
          ),
        ),
      );
      choose(tester, const Offset(100, 100));
      await tester.pumpAndSettle();
      for (final unavailable in ['sold', 'blocked']) {
        update(() => status = unavailable);
        await tester.pump();
        expect(find.text('1 seats selected'), findsOneWidget);
        choose(tester, const Offset(100, 100));
        await tester.pumpAndSettle();
        expect(calls, 1);
        expect(
          find.text('This seat or its paired seat is unavailable.'),
          findsOneWidget,
        );
      }
    },
  );

  testWidgets(
    'replacement closes stale quantity dialog before dispatch and resets accepted quantities',
    (tester) async {
      var doc = document(), calls = 0;
      late StateSetter update;
      await tester.pumpWidget(
        MaterialApp(
          home: StatefulBuilder(
            builder: (context, set) {
              update = set;
              return Scaffold(
                body: VenueLayoutPicker(
                  document: doc,
                  onSelectionRequested: (ids, selecting) async =>
                      const LayoutSelectionResult(accepted: true),
                  onQuantityRequested: (id, value) async {
                    calls++;
                    return const LayoutSelectionResult(accepted: true);
                  },
                ),
              );
            },
          ),
        ),
      );
      choose(tester, const Offset(400, 300));
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('Add one'));
      await tester.pump();
      update(() => doc = document());
      await tester.pumpAndSettle();
      expect(find.text('Confirm quantity'), findsNothing);
      expect(calls, 0);
      choose(tester, const Offset(400, 300));
      await tester.pumpAndSettle();
      expect(
        tester
            .widget<IconButton>(
              find.byWidgetPredicate(
                (w) => w is IconButton && w.tooltip == 'Remove one',
              ),
            )
            .onPressed,
        isNotNull,
      );
      expect(
        find.descendant(of: find.byType(AlertDialog), matching: find.text('1')),
        findsOneWidget,
        reason:
            'A replacement session resets to the public default quantity of one.',
      );
      await tester.tap(find.byTooltip('Add one'));
      await tester.pump();
      await tester.tap(find.text('Confirm quantity'));
      await tester.pumpAndSettle();
      expect(calls, 1);
      update(() => doc = document());
      await tester.pumpAndSettle();
      choose(tester, const Offset(400, 300));
      await tester.pumpAndSettle();
      expect(
        tester
            .widget<IconButton>(
              find.byWidgetPredicate(
                (w) => w is IconButton && w.tooltip == 'Remove one',
              ),
            )
            .onPressed,
        isNotNull,
      );
      expect(
        find.descendant(of: find.byType(AlertDialog), matching: find.text('1')),
        findsOneWidget,
        reason:
            'A replacement session resets to the public default quantity of one.',
      );
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();
    },
  );

  testWidgets(
    'late quantity callback and live unavailable dialog cannot update replacement session',
    (tester) async {
      var doc = document(), calls = 0, status = 'available';
      late StateSetter update;
      final response = Completer<LayoutSelectionResult>();
      await tester.pumpWidget(
        MaterialApp(
          home: StatefulBuilder(
            builder: (context, set) {
              update = set;
              return Scaffold(
                body: VenueLayoutPicker(
                  document: doc,
                  capacityPresentation: {
                    areaId: {'available': 20, 'status': status},
                  },
                  onSelectionRequested: (ids, selecting) async =>
                      const LayoutSelectionResult(accepted: true),
                  onQuantityRequested: (id, value) {
                    calls++;
                    return response.future;
                  },
                ),
              );
            },
          ),
        ),
      );
      choose(tester, const Offset(400, 300));
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('Add one'));
      await tester.pump();
      await tester.tap(find.text('Confirm quantity'));
      await tester.pump();
      update(() => doc = document());
      await tester.pump();
      response.complete(
        const LayoutSelectionResult(accepted: true, message: 'stale quantity'),
      );
      await tester.pumpAndSettle();
      expect(find.text('stale quantity'), findsNothing);
      expect(find.byType(LinearProgressIndicator), findsNothing);
      choose(tester, const Offset(400, 300));
      await tester.pumpAndSettle();
      expect(
        tester
            .widget<IconButton>(
              find.byWidgetPredicate(
                (w) => w is IconButton && w.tooltip == 'Remove one',
              ),
            )
            .onPressed,
        isNotNull,
      );
      expect(
        find.descendant(of: find.byType(AlertDialog), matching: find.text('1')),
        findsOneWidget,
        reason:
            'A replacement session resets to the public default quantity of one.',
      );
      await tester.tap(find.byTooltip('Add one'));
      await tester.pump();
      update(() => status = 'sold');
      await tester.pump();
      await tester.tap(find.text('Confirm quantity'));
      await tester.pumpAndSettle();
      expect(calls, 1);
      expect(find.text('Standing places are unavailable.'), findsOneWidget);
    },
  );
}
