import 'package:fstapp/widgets/dependency_material_bridge.dart';
import 'package:material_ui/material_ui.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fstapp/components/occasion/setup/occasion_setup_appearance_panel.dart';

const _presets = [
  OccasionSetupAppearancePreset(
      id: 'clean',
      label: 'Čistý',
      primaryColor: Colors.blue,
      secondaryColor: Colors.white,
      gradient: false,
      fontFamily: 'Roboto'),
  OccasionSetupAppearancePreset(
      id: 'formal',
      label: 'Slavnostní',
      primaryColor: Colors.blue,
      secondaryColor: Colors.amber,
      gradient: true,
      fontFamily: 'Merriweather'),
];

void main() {
  for (final scale in [1.0, 2.0]) {
    testWidgets(
        'font is visible and resolved; selection keeps card size at ${scale}x',
        (tester) async {
      tester.view.physicalSize = const Size(375, 1000);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      String? selected = 'clean';
      String selectedFont = 'Roboto';
      late StateSetter update;
      await tester.pumpWidget(MaterialApp(builder: DependencyMaterialBridge.builder,
          home: Scaffold(
              body: MediaQuery(
        data: MediaQueryData(
            textScaler: TextScaler.linear(scale), disableAnimations: true),
        child: StatefulBuilder(builder: (context, setState) {
          update = setState;
          return SingleChildScrollView(
              child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: OccasionSetupAppearancePanel(
                    presets: _presets,
                    selectedPresetId: selected,
                    onPresetSelected: (value) => setState(() {
                      selected = value;
                      selectedFont = 'Merriweather';
                    }),
                    fontFamily: selectedFont,
                    fontFamilies: const ['Roboto', 'Merriweather'],
                    onFontChanged: (value) =>
                        setState(() => selectedFont = value),
                    fontStyle: (family, base) =>
                        base.copyWith(fontFamily: '$family-runtime-alias'),
                    primaryColor: Colors.blue,
                    secondaryColor: Colors.red,
                    gradient: false,
                    onPrimaryChanged: (_) {},
                    onSecondaryChanged: (_) {},
                    onGradientChanged: (_) {},
                    formPreview: const Text('Skutečný náhled formuláře'),
                  )));
        }),
      ))));
      final dropdown = find.byType(DropdownButtonFormField<String>);
      expect(dropdown.hitTestable(), findsOneWidget);
      expect(find.byType(SwitchListTile).hitTestable(), findsNothing);
      expect(tester.widget<Text>(find.text('Čistý')).style?.fontFamily,
          'Roboto-runtime-alias');
      expect(tester.widget<Text>(find.text('Slavnostní')).style?.fontFamily,
          'Merriweather-runtime-alias');
      final clean = find.byKey(const ValueKey('appearance-preset-clean'));
      final formal = find.byKey(const ValueKey('appearance-preset-formal'));
      final originalSize = tester.getSize(clean);
      await tester.ensureVisible(formal);
      await tester.tap(formal);
      await tester.pumpAndSettle();
      expect(selected, 'formal');
      expect(tester.getSize(clean), originalSize);
      expect(
          tester.widget<DropdownButtonFormField<String>>(dropdown).initialValue,
          'Merriweather');
      await tester.ensureVisible(dropdown);
      await tester.tap(dropdown);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Roboto').last);
      await tester.pumpAndSettle();
      expect(selectedFont, 'Roboto');
      // Parent-driven font updates also refresh the field's selected value.
      update(() => selectedFont = 'Merriweather');
      await tester.pumpAndSettle();
      expect(
          tester.widget<DropdownButtonFormField<String>>(dropdown).initialValue,
          'Merriweather');
      expect(find.byType(TabBar), findsNothing);
      expect(find.text('Skutečný náhled formuláře'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  }
}
