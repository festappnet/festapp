import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fstapp/components/occasion/setup/occasion_setup_appearance_panel.dart';

void main() {
  testWidgets(
      'presets notify owner and mobile previews switch without source data',
      (tester) async {
    tester.view.physicalSize = const Size(375, 1000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    String? selected;
    bool? gradient;
    await tester.pumpWidget(MaterialApp(
        home: Scaffold(
            body: SingleChildScrollView(
                child: Padding(
      padding: const EdgeInsets.all(16),
      child: OccasionSetupAppearancePanel(
        presets: const [
          OccasionSetupAppearancePreset(
              id: 'clean',
              label: 'Čistý',
              primaryColor: Colors.blue,
              secondaryColor: Colors.white,
              gradient: false,
              fontFamily: 'Roboto')
        ],
        selectedPresetId: null,
        onPresetSelected: (value) => selected = value,
        fontFamily: 'Roboto',
        fontFamilies: const ['Roboto'],
        onFontChanged: (_) {},
        primaryColor: Colors.blue,
        secondaryColor: Colors.red,
        gradient: false,
        onPrimaryChanged: (_) {},
        onSecondaryChanged: (_) {},
        onGradientChanged: (value) => gradient = value,
        formPreview: const Text('Skutečný náhled formuláře'),
        ticketPreview: const Text('Skutečný náhled vstupenky'),
      ),
    )))));
    await tester.tap(find.byKey(const ValueKey('appearance-preset-clean')));
    expect(selected, 'clean');
    await tester.tap(find.byType(SwitchListTile));
    expect(gradient, true);
    expect(find.text('Skutečný náhled formuláře'), findsOneWidget);
    await tester.ensureVisible(find.text('Vstupenka'));
    await tester.tap(find.text('Vstupenka'));
    await tester.pumpAndSettle();
    expect(find.text('Skutečný náhled vstupenky'), findsOneWidget);
    expect(find.text('Skutečný náhled formuláře'), findsNothing);
    expect(tester.takeException(), isNull);
  });
}
