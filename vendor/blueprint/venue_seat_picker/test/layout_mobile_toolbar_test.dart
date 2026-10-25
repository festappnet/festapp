import 'package:material_ui/material_ui.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:venue_seat_picker/venue_seat_picker.dart';
import 'package:venue_seat_picker/src/layout_editor/widgets/layout_scene_surface.dart';

void main() {
  for (final width in [320.0, 390.0]) {
    testWidgets('mobile editor keeps canvas usable at $width with large text', (
      tester,
    ) async {
      tester.view.physicalSize = Size(width, 640);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final controller = VenueLayoutController(VenueLayoutDocument.empty());
      addTearDown(controller.dispose);
      await tester.pumpWidget(
        MaterialApp(
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(
              context,
            ).copyWith(textScaler: const TextScaler.linear(1.6)),
            child: child!,
          ),
          home: Scaffold(
            body: VenueLayoutEditor(
              controller: controller,
          showGallery: false,
              toolbarPrefix: const Text('Edit plan'),
              toolbarTrailing: IconButton(
                onPressed: () {},
                icon: const Icon(Icons.save),
              ),
              libraryOverride: const Center(child: Text('Library content')),
              inspectorOverride: const Center(child: Text('Inspector content')),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      final toolbar = find.byKey(const ValueKey('layout-editor-toolbar'));
      expect(tester.getSize(toolbar).height, lessThanOrEqualTo(112));
      expect(
        tester.getSize(find.byType(LayoutSceneSurface)).height,
        greaterThan(640 * .6),
      );
      expect(tester.takeException(), isNull);
      await tester.tap(find.byKey(const ValueKey('layout-mobile-settings')));
      await tester.pumpAndSettle();
      expect(find.text('Canvas size'), findsOneWidget);
      expect(find.text('Snap'), findsOneWidget);
      expect(find.text('Grid'), findsOneWidget);
      await tester.tapAt(const Offset(10, 600));
      await tester.pumpAndSettle();
      final initialHeight = tester
          .getSize(find.byType(LayoutSceneSurface))
          .height;
      await tester.tap(find.byKey(const ValueKey('layout-mobile-library')));
      await tester.pumpAndSettle();
      expect(find.text('Library content'), findsOneWidget);
      expect(
        tester.getSize(find.byType(LayoutSceneSurface)).height,
        initialHeight,
      );
      expect(tester.takeException(), isNull);
    });
  }
}
