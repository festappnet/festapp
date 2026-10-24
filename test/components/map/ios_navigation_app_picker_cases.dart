import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fstapp/components/map/external_map_navigation.dart';
import 'package:fstapp/components/map/ios_navigation_app_picker.dart';

void main() {
  testWidgets('shows supplied apps and returns the tapped navigation app',
      (tester) async {
    IosNavigationApp? selected;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: IosNavigationAppPicker(
            apps: const [
              IosNavigationApp.appleMaps,
              IosNavigationApp.googleMaps,
              IosNavigationApp.waze,
              IosNavigationApp.mapyCom,
            ],
            title: 'Choose navigation',
            onSelected: (app) => selected = app,
          ),
        ),
      ),
    );

    expect(find.text('Choose navigation'), findsOneWidget);
    expect(find.text('Apple Maps'), findsOneWidget);
    expect(find.text('Google Maps'), findsOneWidget);
    expect(find.text('Waze'), findsOneWidget);
    expect(find.text('Mapy.com'), findsOneWidget);

    await tester.tap(find.text('Google Maps'));
    expect(selected, IosNavigationApp.googleMaps);
  });
}
