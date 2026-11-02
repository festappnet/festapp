import 'dart:ui' as ui;

import 'package:flutter_test/flutter_test.dart';
import 'package:flutter/services.dart';
import 'package:flutter/gestures.dart';
import 'package:material_ui/material_ui.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:fstapp/components/eshop/views/order_detail_split_pane.dart';

import '../../support/fixtures/widget_environment_fixture.dart';

void main() {
  WidgetEnvironmentFixture.register();
  testWidgets(
    'mobile detail covers app chrome, retains state and keeps dialogs above it',
    (tester) async {
      SharedPreferences.setMockInitialValues({});
      await _setViewport(tester, const Size(390, 844));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final environment = WidgetEnvironmentFixture(
        locale: const Locale('en'),
        translations: {},
      );
      var opened = true;
      var globalTaps = 0;
      late StateSetter updateHost;
      final editor = TextEditingController();
      addTearDown(editor.dispose);
      await environment.pumpWidget(
        tester,
        MaterialApp(
          home: StatefulBuilder(
            builder: (context, setState) {
              updateHost = setState;
              return Scaffold(
                appBar: AppBar(
                  title: TextButton(
                    onPressed: () => globalTaps++,
                    child: const Text('Global navigation'),
                  ),
                ),
                body: Padding(
                  padding: const EdgeInsets.all(16),
                  child: OrderDetailSplitPane(
                    table: const Text('Orders table'),
                    detail: !opened
                        ? null
                        : Builder(
                            builder: (detailContext) => Column(
                              children: [
                                TextField(controller: editor),
                                TextButton(
                                  onPressed: () => showDialog<void>(
                                    context: detailContext,
                                    builder: (_) => const AlertDialog(
                                      title: Text('Nested dialog'),
                                    ),
                                  ),
                                  child: const Text('Open dialog'),
                                ),
                                TextButton(
                                  onPressed: () =>
                                      updateHost(() => opened = false),
                                  child: const Text('Close detail'),
                                ),
                              ],
                            ),
                          ),
                  ),
                ),
              );
            },
          ),
        ),
      );
      await tester.pumpAndSettle();
      final pane = find.byKey(const ValueKey('order-detail-pane'));
      expect(tester.getRect(pane), const Rect.fromLTWH(0, 0, 390, 844));
      expect(find.text('Global navigation').hitTestable(), findsNothing);
      await tester.enterText(find.byType(TextField), 'Unsaved note');
      final originalFieldState = tester.state(find.byType(TextField));
      await tester.tap(find.text('Open dialog'));
      await tester.pumpAndSettle();
      expect(find.text('Nested dialog').hitTestable(), findsOneWidget);
      Navigator.of(
        tester.element(find.byType(AlertDialog)),
        rootNavigator: true,
      ).pop();
      await tester.pumpAndSettle();
      await _setViewport(tester, const Size(1500, 844));
      await tester.pumpAndSettle();
      expect(
        identical(tester.state(find.byType(TextField)), originalFieldState),
        isTrue,
      );
      expect(editor.text, 'Unsaved note');
      expect(find.text('Global navigation').hitTestable(), findsOneWidget);
      await _setViewport(tester, const Size(390, 844));
      await tester.pumpAndSettle();
      expect(
        identical(tester.state(find.byType(TextField)), originalFieldState),
        isTrue,
      );
      await tester.tap(find.text('Close detail'));
      await tester.pumpAndSettle();
      expect(pane, findsNothing);
      expect(find.text('Orders table'), findsOneWidget);
      await tester.tap(find.text('Global navigation'));
      expect(globalTaps, 1);
      expect(tester.takeException(), isNull);
    },
  );
  testWidgets(
    'divider persists bounded width and preserves it across mobile layouts',
    (tester) async {
      final semantics = tester.ensureSemantics();
      try {
        SharedPreferences.setMockInitialValues({});
        final environment = WidgetEnvironmentFixture(
          locale: const Locale('en'),
          translations: {
            'OrderDetail': {'resize_panel': 'Resize order detail'},
          },
        );
        await _setViewport(tester, const Size(1500, 800));
        addTearDown(() => tester.binding.setSurfaceSize(null));
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        Widget host() => MaterialApp(
          home: Scaffold(
            body: OrderDetailSplitPane(
              table: const Text('Orders'),
              detail: const Text('Detail'),
            ),
          ),
        );
        await environment.pumpWidget(tester, host());
        await tester.pumpAndSettle();
        final panel = find.byKey(const ValueKey('order-detail-pane'));
        final divider = find.byKey(const ValueKey('order-detail-resize'));
        double width() => tester.getSize(panel).width;
        expect(width(), 720);
        await tester.drag(divider, const Offset(120, 0));
        await tester.pumpAndSettle();
        expect(width(), 600);
        final accessibleDivider = tester.getSemantics(
          find.bySemanticsLabel('Resize order detail'),
        );
        expect(
          accessibleDivider.getSemanticsData().hasAction(
            ui.SemanticsAction.increase,
          ),
          isTrue,
        );
        expect(
          accessibleDivider.getSemanticsData().hasAction(
            ui.SemanticsAction.decrease,
          ),
          isTrue,
        );
        tester.binding.pipelineOwner.semanticsOwner!.performAction(
          accessibleDivider.id,
          ui.SemanticsAction.increase,
        );
        await tester.pumpAndSettle();
        expect(width(), 632);
        tester.binding.pipelineOwner.semanticsOwner!.performAction(
          accessibleDivider.id,
          ui.SemanticsAction.decrease,
        );
        await tester.pumpAndSettle();
        expect(width(), 600);
        await tester.drag(divider, const Offset(-100, 0));
        await tester.pumpAndSettle();
        expect(width(), 700);
        final prefs = await SharedPreferences.getInstance();
        expect(prefs.getDouble(OrderDetailSplitPane.preferenceKey), 700);
        await environment.pumpWidget(tester, const SizedBox());
        await environment.pumpWidget(tester, host());
        await tester.pumpAndSettle();
        expect(width(), 700);
        await _setViewport(tester, const Size(700, 800));
        await tester.pumpAndSettle();
        expect(width(), 700);
        expect(divider, findsNothing);
        expect(prefs.getDouble(OrderDetailSplitPane.preferenceKey), 700);
        await _setViewport(tester, const Size(1500, 800));
        await tester.pumpAndSettle();
        expect(width(), 700);
        await tester.drag(divider, const Offset(-1000, 0));
        await tester.pumpAndSettle();
        expect(width(), 760);
        await tester.drag(divider, const Offset(1000, 0));
        await tester.pumpAndSettle();
        expect(width(), 360);
        await tester.tap(divider);
        await tester.sendKeyEvent(LogicalKeyboardKey.arrowLeft);
        await tester.pumpAndSettle();
        expect(width(), 392);
        expect(prefs.getDouble(OrderDetailSplitPane.preferenceKey), 392);
        final grab = await tester.startGesture(
          tester.getCenter(divider) + const Offset(8, 0),
        );
        await grab.moveBy(const Offset(-40, 0));
        await grab.up();
        await tester.pumpAndSettle();
        expect(width(), 432);
        final line = find.byKey(const ValueKey('order-detail-divider-line'));
        expect(find.byKey(const ValueKey('order-detail-grip')), findsNothing);
        expect(find.byIcon(Icons.drag_handle), findsNothing);
        expect(tester.getSize(divider).width, 40);
        expect(
          tester.getCenter(divider).dx,
          closeTo(tester.getCenter(line).dx, .01),
        );
        expect(tester.getSize(divider).height, tester.getSize(line).height);
        for (final offset in [-18.0, 18.0]) {
          final lineRect = tester.getRect(line);
          final target = Offset(
            lineRect.center.dx + offset,
            offset < 0 ? lineRect.top + 20 : lineRect.bottom - 20,
          );
          final before = width();
          final drag = await tester.startGesture(target);
          // The resize cursor promises immediate dragging, including movements
          // smaller than a gesture recognizer's drag slop.
          await drag.moveBy(const Offset(-1, 0));
          await tester.pump();
          expect(width(), before + 1);
          await drag.moveBy(const Offset(-19, 0));
          await drag.up();
          await tester.pumpAndSettle();
          expect(width(), before + 20);
        }
        final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
        await mouse.addPointer(location: tester.getCenter(divider));
        for (final y in [20.0, 400.0, 780.0]) {
          for (final offset in [-22.0, -18.0, 0.0, 18.0, 22.0]) {
            final target = Offset(tester.getCenter(line).dx + offset, y);
            await mouse.moveTo(target);
            await tester.pump();
            final showsResize =
                tester.binding.mouseTracker.debugDeviceActiveCursor(1) ==
                SystemMouseCursors.resizeLeftRight;
            expect(showsResize, offset.abs() < 20);
            final before = width();
            await mouse.down(target);
            await mouse.moveBy(const Offset(1, 0));
            await tester.pump();
            expect(width(), before - (showsResize ? 1 : 0));
            await mouse.up();
            await tester.pump();
          }
        }
        await mouse.moveTo(tester.getCenter(divider));
        await tester.pump();
        expect(
          tester.binding.mouseTracker.debugDeviceActiveCursor(1),
          SystemMouseCursors.resizeLeftRight,
        );
        await mouse.down(tester.getCenter(divider));
        await mouse.moveTo(const Offset(100, 400));
        await tester.pump();
        expect(width(), OrderDetailSplitPane.maxDetailWidth);
        // Captured dragging still works here, far outside the idle target.
        expect(
          tester.binding.mouseTracker.debugDeviceActiveCursor(1),
          SystemMouseCursors.resizeLeftRight,
        );
        await mouse.moveBy(const Offset(1, 0));
        await tester.pump();
        expect(width(), OrderDetailSplitPane.maxDetailWidth - 1);
        await mouse.up();
        await tester.pump();
        expect(
          tester.binding.mouseTracker.debugDeviceActiveCursor(1),
          isNot(SystemMouseCursors.resizeLeftRight),
        );
        await mouse.moveTo(tester.getCenter(divider));
        await mouse.down(tester.getCenter(divider));
        await mouse.moveTo(const Offset(1400, 400));
        await tester.pump();
        expect(width(), OrderDetailSplitPane.minDetailWidth);
        expect(
          tester.binding.mouseTracker.debugDeviceActiveCursor(1),
          SystemMouseCursors.resizeLeftRight,
        );
        await mouse.moveBy(const Offset(-1, 0));
        await tester.pump();
        expect(width(), OrderDetailSplitPane.minDetailWidth + 1);
        await mouse.cancel();
        await mouse.moveTo(const Offset(1400, 400));
        await tester.pump();
        expect(
          tester.binding.mouseTracker.debugDeviceActiveCursor(1),
          isNot(SystemMouseCursors.resizeLeftRight),
        );
        await mouse.moveTo(tester.getCenter(divider));
        await mouse.down(tester.getCenter(divider));
        await mouse.moveTo(const Offset(100, 400));
        await tester.pump();
        tester.binding.handleAppLifecycleStateChanged(
          AppLifecycleState.inactive,
        );
        await tester.pump();
        expect(
          tester.binding.mouseTracker.debugDeviceActiveCursor(1),
          isNot(SystemMouseCursors.resizeLeftRight),
        );
        await mouse.up();
        tester.binding.handleAppLifecycleStateChanged(
          AppLifecycleState.resumed,
        );
        await mouse.moveTo(tester.getCenter(divider));
        final beforeNewDrag = width();
        await mouse.down(tester.getCenter(divider));
        await mouse.moveBy(const Offset(1, 0));
        await tester.pump();
        expect(width(), beforeNewDrag - 1);
        await environment.pumpWidget(tester, const SizedBox());
        await mouse.cancel();
        await mouse.removePointer();
        expect(tester.takeException(), isNull);
      } finally {
        semantics.dispose();
      }
    },
  );
}

Future<void> _setViewport(WidgetTester tester, Size size) async {
  tester.view.devicePixelRatio = 1;
  tester.view.physicalSize = size;
  await tester.binding.setSurfaceSize(size);
}
