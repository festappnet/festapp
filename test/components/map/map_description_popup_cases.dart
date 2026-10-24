import '../../support/fixtures/localization_log_fixture.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fstapp/components/map/map_description_popup.dart';
import 'package:fstapp/components/map/map_place_model.dart';
import 'package:latlong2/latlong.dart';

void main() {
  // This suite intentionally uses untranslated key fallback (no catalog).
  setUp(() {
    final logs = LocalizationLogFixture.install(expectedMissingCatalog: true);
    addTearDown(logs.dispose);
  });
  testWidgets('popup offers an explicit close action', (tester) async {
    var closed = false;

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: MapDescriptionPopup(
            place: MapPlaceModel(
              id: 1,
              title: 'Stage',
              description: 'Programme details',
              latLng: const LatLng(49.82, 18.26),
            ),
            isEditing: false,
            onClose: () => closed = true,
          ),
        ),
      ),
    );

    await tester.tap(find.byTooltip('Close'));

    expect(closed, isTrue);
  });

  testWidgets('popup offers an obvious navigation action', (tester) async {
    var navigated = false;

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: MapDescriptionPopup(
            place: MapPlaceModel(
              id: 1,
              title: 'WC',
              latLng: const LatLng(49.82, 18.26),
            ),
            isEditing: false,
            onClose: () {},
            onNavigate: () => navigated = true,
          ),
        ),
      ),
    );

    await tester.tap(find.byType(FilledButton));

    expect(navigated, isTrue);
  });
}
