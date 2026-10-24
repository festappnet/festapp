import '../../support/fixtures/localization_log_fixture.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fstapp/components/groups/group_place_dialog.dart';
import 'package:festapp_core/map.dart';

void main() {
  // This suite intentionally uses untranslated key fallback (no catalog).
  setUp(() {
    final logs = LocalizationLogFixture.install(expectedMissingCatalog: true);
    addTearDown(logs.dispose);
  });
  Widget testApp(
    Key openDialogKey,
    ValueChanged<Object?> onResult,
    List<PlaceModel> places,
  ) {
    return MaterialApp(
      home: Scaffold(
        body: Builder(
          builder: (dialogContext) => ElevatedButton(
            key: openDialogKey,
            onPressed: () async {
              onResult(await showDialog<Object?>(
                context: dialogContext,
                builder: (_) => GroupPlaceDialog(
                  places: places,
                  currentPlace: null,
                ),
              ));
            },
            child: const SizedBox.shrink(),
          ),
        ),
      ),
    );
  }

  testWidgets('selects a searchable existing place', (tester) async {
    Object? result;
    final openDialogKey = UniqueKey();
    final place = PlaceModel();
    await tester.pumpWidget(
      testApp(openDialogKey, (value) => result = value, [place]),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(openDialogKey));
    await tester.pumpAndSettle();
    expect(find.byIcon(Icons.place_outlined), findsOneWidget);
    expect(find.byIcon(Icons.add_location_alt_outlined), findsOneWidget);

    await tester.tap(find.byIcon(Icons.place_outlined));
    await tester.pumpAndSettle();
    await tester.tap(find.byType(ListTile).last);
    await tester.pumpAndSettle();

    expect(result, same(place));
  });

  testWidgets('keeps the custom map-point path available', (tester) async {
    Object? result;
    final openDialogKey = UniqueKey();
    await tester.pumpWidget(
      testApp(openDialogKey, (value) => result = value, []),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(openDialogKey));
    await tester.pumpAndSettle();
    await tester.tap(find.byIcon(Icons.add_location_alt_outlined));
    await tester.pumpAndSettle();

    expect(result, isA<UseCustomGroupLocationAction>());
  });
}
