import '../../support/fixtures/localization_log_fixture.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fstapp/components/users/companion/companion_accommodation_field.dart';
import 'package:fstapp/components/users/companion/companion_model.dart';
import 'package:festapp_core/map.dart';

void main() {
  // This suite intentionally uses untranslated key fallback (no catalog).
  setUp(() {
    final logs = LocalizationLogFixture.install(expectedMissingCatalog: true);
    addTearDown(logs.dispose);
  });
  testWidgets('shows companion accommodation and opens its map place',
      (tester) async {
    int? openedPlaceId;
    final companion = CompanionModel(
      id: 'companion',
      name: 'Ada',
      accommodationPlace: PlaceModel(id: 73, title: 'Domov mládeže A'),
      eventIds: const [],
    );

    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: CompanionAccommodationField(
          companion: companion,
          onOpenPlace: (id) => openedPlaceId = id,
        ),
      ),
    ));

    expect(find.text('Domov mládeže A'), findsOneWidget);
    await tester.tap(find.byType(InkWell));
    expect(openedPlaceId, 73);
  });

  testWidgets('shows an explicit value when accommodation is not assigned',
      (tester) async {
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: CompanionAccommodationField(
          companion: CompanionModel(
            id: 'companion',
            name: 'Ada',
            eventIds: const [],
          ),
          onOpenPlace: (_) {},
        ),
      ),
    ));

    expect(find.text('Inventory.accommodationNotSpecified'), findsOneWidget);
    expect(find.byType(InkWell), findsNothing);
  });
}
