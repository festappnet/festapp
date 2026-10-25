import 'package:fstapp/widgets/dependency_material_bridge.dart';
import 'package:flutter/gestures.dart';
import 'package:material_ui/material_ui.dart';
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
      await tester.pumpWidget(MaterialApp(builder: DependencyMaterialBridge.builder,
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
    await tester.pumpWidget(MaterialApp(builder: DependencyMaterialBridge.builder,
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
  for (final brightness in Brightness.values) {
    testWidgets('full occasion title on hover in $brightness', (tester) async {
      const title =
          'Helpni víkendovka v komunitě s přípravou programu a společným setkáním všech dobrovolníků';
      var opened = false;
      await tester.pumpWidget(
        MaterialApp(builder: DependencyMaterialBridge.builder,
          theme: ThemeData(brightness: brightness),
          home: Scaffold(
            body: Center(
              child: SizedBox(
                width: 320,
                height: 130,
                child: OccasionEditCard(
                  occasion: OccasionModel(
                    title: title,
                    isOpen: true,
                    isHidden: false,
                    isPromoted: false,
                  ),
                  onTap: () => opened = true,
                ),
              ),
            ),
          ),
        ),
      );
      final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
      addTearDown(mouse.removePointer);
      await mouse.addPointer(location: Offset.zero);
      await mouse.moveTo(tester.getCenter(find.text(title)));
      await tester.pump(const Duration(milliseconds: 300));
      expect(find.text(title), findsOneWidget);
      await tester.pump(const Duration(milliseconds: 250));
      await tester.pump(const Duration(milliseconds: 200));
      expect(find.text(title), findsNWidgets(2));
      final bubble = tester.getRect(find.text(title).last);
      expect(bubble.width, lessThanOrEqualTo(360));
      expect(bubble.height, greaterThan(35));
      await tester.tap(find.text(title).first);
      expect(opened, isTrue);
      await mouse.moveTo(Offset.zero);
      await tester.pumpAndSettle();
      expect(find.text(title), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  }
}
