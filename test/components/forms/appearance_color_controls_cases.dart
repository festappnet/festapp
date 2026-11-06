import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:fstapp/components/_shared/appearance_color_strings.dart';
import 'package:fstapp/widgets/appearance_color_controls.dart';
import 'package:fstapp/widgets/dependency_material_bridge.dart';

import '../../support/fixtures/widget_environment_fixture.dart';

void main() {
  WidgetEnvironmentFixture.register();
  late WidgetEnvironmentFixture environment;
  setUpAll(() {
    environment = WidgetEnvironmentFixture(
      locale: const Locale('cs'),
      translations: jsonDecode(
        File('assets/translations/cs.json').readAsStringSync(),
      ),
    );
  });

  for (final width in [320.0, 390.0, 800.0]) {
    for (final scale in [1.0, 2.0]) {
      testWidgetsWithEnvironment(
        () => environment,
        'color controls fit ${width}px at ${scale}x and support keyboard editing',
        (tester) async {
          tester.view.physicalSize = Size(width, 1000);
          tester.view.devicePixelRatio = 1;
          addTearDown(tester.view.resetPhysicalSize);
          addTearDown(tester.view.resetDevicePixelRatio);
          var gradient = false;
          var primaryEdits = 0;
          var secondaryEdits = 0;
          await environment.pumpWidget(
            tester,
            MaterialApp(
              builder: DependencyMaterialBridge.builder,
              home: Scaffold(
                body: MediaQuery(
                  data: MediaQueryData(textScaler: TextScaler.linear(scale)),
                  child: StatefulBuilder(
                    builder: (context, setState) => SingleChildScrollView(
                      child: Padding(
                        padding: const EdgeInsets.all(16),
                        child: AppearanceColorControls(
                          paletteName: 'Přírodní',
                          gradient: gradient,
                          primaryColor: const Color(0xff216445),
                          secondaryColor: const Color(0xff146475),
                          onGradientChanged: (value) =>
                              setState(() => gradient = value),
                          onPrimaryPressed: () => primaryEdits++,
                          onSecondaryPressed: () => secondaryEdits++,
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          );
          final primary = find.byKey(
            const ValueKey('appearance-color-primary'),
          );
          final secondary = find.byKey(
            const ValueKey('appearance-color-secondary'),
          );
          expect(
            find.text('${AppearanceColorStrings.theme} - Přírodní'),
            findsOneWidget,
          );
          expect(find.text('#216445'), findsOneWidget);
          expect(secondary, findsNothing);
          // Tab traversal reaches the native button; Enter invokes the same edit action.
          for (var i = 0; i < 5 && primaryEdits == 0; i++) {
            await tester.sendKeyEvent(LogicalKeyboardKey.tab);
            await tester.pump();
            if (tester
                .widget<SwitchListTile>(find.byType(SwitchListTile))
                .value) {
              fail('Tab must not change the color mode');
            }
            final focus = FocusManager.instance.primaryFocus;
            if (focus?.context != null &&
                focus!.context!
                        .findAncestorWidgetOfExactType<OutlinedButton>() !=
                    null) {
              await tester.sendKeyEvent(LogicalKeyboardKey.enter);
              await tester.pump();
            }
          }
          expect(primaryEdits, 1);
          await tester.tap(find.byType(SwitchListTile));
          await tester.pumpAndSettle();
          expect(
            find.text('${AppearanceColorStrings.first} - Přírodní'),
            findsOneWidget,
          );
          expect(
            find.text('${AppearanceColorStrings.second} - Přírodní'),
            findsOneWidget,
          );
          if (width >= 600 && scale == 1) {
            expect(
              tester.getTopLeft(secondary).dy,
              tester.getTopLeft(primary).dy,
            );
          } else {
            expect(
              tester.getTopLeft(secondary).dy,
              greaterThan(tester.getBottomLeft(primary).dy),
            );
          }
          await tester.ensureVisible(secondary);
          await tester.tap(secondary);
          expect(secondaryEdits, 1);
          await tester.ensureVisible(find.byType(SwitchListTile));
          await tester.tap(find.byType(SwitchListTile));
          await tester.pumpAndSettle();
          expect(secondary, findsNothing);
          expect(tester.takeException(), isNull);
        },
      );
    }
  }
}
