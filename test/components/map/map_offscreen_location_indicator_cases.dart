import 'package:fstapp/widgets/dependency_material_bridge.dart';
import '../../support/fixtures/localization_log_fixture.dart';
import 'package:material_ui/material_ui.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fstapp/components/map/map_current_location_drop.dart';
import 'package:fstapp/components/map/map_offscreen_location_indicator.dart';
import 'package:fstapp/components/map/map_location_style.dart';

Widget _app(Offset target, {VoidCallback? onPressed}) => MaterialApp(builder: DependencyMaterialBridge.builder,
      home: Scaffold(
        body: SizedBox(
          width: 400,
          height: 800,
          child: Stack(
            children: [
              MapOffscreenLocationIndicator(
                projectedLocation: target,
                occupiedRectsBuilder: (viewport) => [
                  Rect.fromLTRB(0, 0, viewport.width, 100),
                  Rect.fromLTRB(
                    100,
                    viewport.height - 120,
                    300,
                    viewport.height,
                  ),
                ],
                onPressed: onPressed ?? () {},
              ),
            ],
          ),
        ),
      ),
    );

void main() {
  // This suite intentionally uses untranslated key fallback (no catalog).
  setUp(() {
    final logs = LocalizationLogFixture.install(expectedMissingCatalog: true);
    addTearDown(logs.dispose);
  });
  testWidgets('shows a bare edge drop only while location is off-screen',
      (tester) async {
    tester.view.physicalSize = const Size(400, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(_app(const Offset(900, 390)));
    expect(find.byIcon(Icons.location_pin), findsNothing);
    final dropFinder = find.byKey(MapOffscreenLocationIndicator.dropKey);
    expect(dropFinder, findsOneWidget);
    final drop = tester.widget<MapCurrentLocationDrop>(dropFinder);
    expect(drop.color, MapLocationStyle.color);
    expect(drop.size, 42);
    expect(
      tester.getCenter(dropFinder).dx,
      closeTo(379, 0.01),
    );

    await tester.pumpWidget(_app(const Offset(200, 390)));
    expect(dropFinder, findsNothing);

    await tester.pumpWidget(_app(const Offset(-500, 390)));
    expect(dropFinder, findsOneWidget);
    expect(
      tester.getCenter(dropFinder).dx,
      closeTo(21, 0.01),
    );
  });

  testWidgets('forwards a tap on the off-screen drop', (tester) async {
    tester.view.physicalSize = const Size(400, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    var presses = 0;

    await tester.pumpWidget(
      _app(const Offset(900, 390), onPressed: () => presses++),
    );
    await tester.tap(find.byKey(MapOffscreenLocationIndicator.dropKey));

    expect(presses, 1);
  });
}
