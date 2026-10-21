import 'package:flutter/gestures.dart';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fstapp/components/blueprint/blueprint_seat_state.dart';
import 'package:fstapp/components/blueprint/blueprint_strings.dart';
import 'package:fstapp/components/blueprint/views/blueprint_layout_legend.dart';
import '../../support/fixtures/widget_environment_fixture.dart';

void main() {
  WidgetEnvironmentFixture.register();
  late WidgetEnvironmentFixture environment;
  setUpAll(() {
    environment = WidgetEnvironmentFixture(
        locale: const Locale('cs'),
        translations:
            jsonDecode(File('assets/translations/cs.json').readAsStringSync())
                as Map<String, dynamic>);
  });
  testWidgetsWithEnvironment(() => environment,
      'legend hover highlights its state without selecting seats',
      (tester) async {
    BlueprintSeatState? hovered;
    await environment.pumpWidget(
        tester,
        MaterialApp(
            home: Scaffold(
                body: BlueprintLayoutLegend(
                    compact: true,
                    states: const [BlueprintSeatState.available],
                    onHover: (state) => hovered = state))));
    final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
    await mouse.addPointer(location: const Offset(799, 599));
    await mouse.moveTo(tester.getCenter(
        find.byKey(const ValueKey('blueprint-legend-hover-available'))));
    await tester.pump();
    expect(hovered, BlueprintSeatState.available);
    await mouse.moveTo(const Offset(799, 599));
    await tester.pump();
    expect(hovered, isNull);
    await mouse.removePointer();
  });
  testWidgetsWithEnvironment(() => environment,
      'mobile legend stays one row and exposes every state by horizontal scrolling',
      (tester) async {
    await environment.pumpWidget(tester, MaterialApp(home: Scaffold(body: Align(
      alignment: Alignment.topCenter,
      child: SizedBox(width: 360, child: BlueprintLayoutLegend(
        compact: true, states: const [BlueprintSeatState.available])),
    ))));
    final legend = find.byKey(const ValueKey('blueprint-seat-legend'));
    final scroll = find.byKey(const ValueKey('blueprint-legend-scroll'));
    expect(tester.getSize(legend).height, lessThanOrEqualTo(60));
    expect(scroll, findsOneWidget);
    await tester.drag(scroll, const Offset(-900, 0));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('blueprint-legend-hover-selectedByMe')).hitTestable(),
        findsOneWidget);
    expect(tester.takeException(), isNull);
  });
  for (final brightness in Brightness.values) {
    for (final compact in [false, true]) {
      testWidgetsWithEnvironment(() => environment,
          'legend compact=$compact explains markers in $brightness at narrow width and large type',
          (tester) async {
        await environment.pumpWidget(
            tester,
            MaterialApp(
              theme: ThemeData(brightness: brightness),
              home: Scaffold(
                  body: Center(
                      child: SizedBox(
                width: 260,
                child: MediaQuery(
                    data: const MediaQueryData(
                        textScaler: TextScaler.linear(1.6),
                        disableAnimations: true),
                    child: SingleChildScrollView(
                        child: BlueprintLayoutLegend(
                            compact: compact,
                            states: const [
                          BlueprintSeatState.available,
                          BlueprintSeatState.available,
                          BlueprintSeatState.used,
                          BlueprintSeatState.blocked,
                        ]))),
              ))),
            ));
        expect(find.text(BlueprintStrings.helpSeatStates),
            compact ? findsNothing : findsOneWidget);
        expect(find.text('${BlueprintStrings.seatState('available')} (2)'),
            findsOneWidget);
        for (final state in ['used', 'blocked']) {
          final description = BlueprintStrings.seatStateDescription(state);
          if (compact) {
            expect(find.text(description), findsNothing);
            expect(find.byTooltip(description), findsOneWidget);
          } else {
            expect(find.text(description), findsOneWidget);
          }
        }
        expect(find.byIcon(Icons.check), findsOneWidget);
        expect(find.byIcon(Icons.close), findsOneWidget);
        expect(find.textContaining('FeatureBlueprint.'), findsNothing);
        expect(tester.takeException(), isNull);
      });
    }
  }
}
