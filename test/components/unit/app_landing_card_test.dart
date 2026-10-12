import 'package:flutter/material.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fstapp/components/occasion/occasion_model.dart';
import 'package:fstapp/components/unit/unit_strings.dart';
import 'package:fstapp/components/unit/views/occasion_edit_card.dart';

void main() {
  setUpAll(() => initializeDateFormatting());
  for (final selected in [false, true]) {
    testWidgets('landing menu and marker selected=$selected', (tester) async {
      var called = false;
      await tester.pumpWidget(MaterialApp(
          home: Scaffold(
              body: SizedBox(
                  width: 320,
                  height: 110,
                  child: OccasionEditCard(
                    occasion: OccasionModel(
                        id: 1,
                        title: 'Festival Slunovrat',
                        startTime: DateTime(2026, 6, 18),
                        endTime: DateTime(2026, 6, 20),
                        isOpen: true,
                        isHidden: false,
                        isPromoted: false),
                    isAppLanding: selected,
                    onTap: () {},
                    onCreateCopy: () {},
                    onSetAppLanding: () => called = true,
                  )))));
      expect(find.byIcon(Icons.home), selected ? findsOneWidget : findsNothing);
      await tester.tap(find.byIcon(Icons.more_vert));
      await tester.pumpAndSettle();
      await tester.tap(find.text(
          selected ? UnitStrings.clearAppLanding : UnitStrings.setAppLanding));
      await tester.pumpAndSettle();
      expect(called, isTrue);
      expect(tester.takeException(), isNull);
    });
  }
  testWidgets('read-only card has no landing command', (tester) async {
    await tester.pumpWidget(MaterialApp(
        home: Scaffold(
            body: OccasionEditCard(
      occasion: OccasionModel(
          title: 'Festival',
          startTime: DateTime(2026),
          endTime: DateTime(2026, 2),
          isOpen: true,
          isHidden: false,
          isPromoted: false),
      onTap: () {},
      onCreateCopy: () {},
      isAppLanding: true,
    ))));
    await tester.tap(find.byIcon(Icons.more_vert));
    await tester.pumpAndSettle();
    expect(find.text(UnitStrings.clearAppLanding), findsNothing);
    expect(find.text(UnitStrings.setAppLanding), findsNothing);
  });
}
