import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:venue_seat_picker/venue_seat_picker.dart';
import 'package:venue_seat_picker/src/layout_editor/widgets/layout_scene_surface.dart';

void main() {
  Future<VenueLayoutController> open(
    WidgetTester tester, {
    bool czech = false,
  }) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final controller = VenueLayoutController(VenueLayoutDocument.empty());
    addTearDown(controller.dispose);
    await tester.pumpWidget(
      MaterialApp(
        locale: Locale(czech ? 'cs' : 'en'),
        supportedLocales: VenueLayoutLocalizations.supportedLocales,
        localizationsDelegates: VenueLayoutLocalizations.localizationsDelegates,
        home: Scaffold(
          body: VenueLayoutEditor(controller: controller, showGallery: false),
        ),
      ),
    );
    await tester.pumpAndSettle();
    return controller;
  }

  Future<void> choose(
    WidgetTester tester,
    String search,
    String title, {
    bool czech = false,
  }) async {
    await tester.tap(find.byKey(const ValueKey('layout-mobile-library')));
    await tester.pumpAndSettle();
    expect(find.byType(Draggable<String>), findsNothing);
    expect(
      find.text(
        czech
            ? 'Klepnutím přidáte objekt. Kreslení pokračuje v plánku.'
            : 'Tap an object to add it. Drawing tools continue on the plan.',
      ),
      findsOneWidget,
    );
    await tester.enterText(
      find.widgetWithText(TextField, czech ? 'Hledat objekt' : 'Find object'),
      search,
    );
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(OutlinedButton, title));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('layout-palette')), findsNothing);
  }

  for (final czech in [false, true]) {
    testWidgets(
      'mobile tap inserts one seat, selects it and supports undo (cs=$czech)',
      (tester) async {
        final c = await open(tester, czech: czech);
        final before = c.document.toJson();
        await choose(
          tester,
          czech ? 'Židle' : 'Seat',
          czech ? 'Židle' : 'Seat',
          czech: czech,
        );
        expect(c.document.nodes.where((n) => n.kind == 'seat'), hasLength(1));
        expect(c.selection, {c.document.nodes.single.id});
        expect(c.error, isNull);
        expect(c.gestureActive, isFalse);
        await choose(
          tester,
          czech ? 'Židle' : 'Seat',
          czech ? 'Židle' : 'Seat',
          czech: czech,
        );
        final seats = c.document.nodes.where((n) => n.kind == 'seat').toList();
        expect(seats, hasLength(2));
        expect(
          Offset(seats[0].x, seats[0].y),
          isNot(Offset(seats[1].x, seats[1].y)),
        );
        c.undo();
        c.undo();
        expect(c.document.toJson(), before);
        expect(c.canUndo, isFalse);
        expect(tester.takeException(), isNull);
      },
    );
  }

  testWidgets('mobile tap inserts a complete table as one undo step', (
    tester,
  ) async {
    final c = await open(tester);
    final before = c.document.toJson();
    await choose(tester, 'Table', 'Table');
    expect(c.document.nodes.where((n) => n.kind == 'table'), hasLength(1));
    expect(c.document.nodes.where((n) => n.kind == 'seat'), isNotEmpty);
    expect(c.error, isNull);
    c.undo();
    expect(c.document.toJson(), before);
    expect(c.canUndo, isFalse);
  });

  testWidgets(
    'mobile drawing choice closes the library and continues on the canvas',
    (tester) async {
      final c = await open(tester);
      await choose(tester, 'Draw bar', 'Paint bar');
      expect(c.document.nodes, isEmpty);
      final surface = tester.widget<LayoutSceneSurface>(
        find.byType(LayoutSceneSurface),
      );
      surface.onPointTap!(const Offset(600, 600));
      await tester.pumpAndSettle();
      expect(c.document.nodes, isNotEmpty);
      expect(c.error, isNull);
      c.undo();
      expect(c.document.nodes, isEmpty);
    },
  );

  testWidgets('mobile object list scrolls by touch without inserting', (
    tester,
  ) async {
    final c = await open(tester);
    await tester.tap(find.byKey(const ValueKey('layout-mobile-library')));
    await tester.pumpAndSettle();
    await tester.drag(
      find.widgetWithText(OutlinedButton, 'Seat'),
      const Offset(0, -240),
      kind: PointerDeviceKind.touch,
    );
    await tester.pumpAndSettle();
    expect(c.document.nodes, isEmpty);
    expect(find.byKey(const ValueKey('layout-palette')), findsOneWidget);
    expect(find.text('Seat').hitTestable(), findsNothing);
    expect(tester.takeException(), isNull);
  });
}
