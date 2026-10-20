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
  for (final brightness in Brightness.values) {
    testWidgetsWithEnvironment(() => environment,
        'legend explains map markers with readable text in $brightness at narrow width and large type',
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
                  child: const SingleChildScrollView(
                      child: BlueprintLayoutLegend(states: [
                    BlueprintSeatState.available,
                    BlueprintSeatState.available,
                    BlueprintSeatState.used,
                    BlueprintSeatState.blocked,
                  ]))),
            ))),
          ));
      expect(find.text(BlueprintStrings.helpSeatStates), findsOneWidget);
      expect(find.text('${BlueprintStrings.seatState('available')} (2)'),
          findsOneWidget);
      expect(find.text(BlueprintStrings.seatStateDescription('used')),
          findsOneWidget);
      expect(find.text(BlueprintStrings.seatStateDescription('blocked')),
          findsOneWidget);
      expect(find.byIcon(Icons.check), findsOneWidget);
      expect(find.byIcon(Icons.close), findsOneWidget);
      expect(find.textContaining('FeatureBlueprint.'), findsNothing);
      expect(tester.takeException(), isNull);
    });
  }
}
