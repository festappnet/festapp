import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fstapp/components/map/map_download_indicator.dart';

void main() {
  testWidgets('checking an existing cache is visually silent', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: MapDownloadIndicator(
            state: MapDownloadCheckingCache(),
            useOffline: true,
          ),
        ),
      ),
    );

    expect(find.byType(CircularProgressIndicator), findsNothing);
    expect(find.byIcon(Icons.check), findsNothing);
  });

  testWidgets('an actual download shows one determinate percentage indicator',
      (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: MapDownloadIndicator(
            state: MapDownloading(0.42),
            useOffline: true,
          ),
        ),
      ),
    );

    expect(find.byType(CircularProgressIndicator), findsOneWidget);
    final indicator = tester.widget<CircularProgressIndicator>(
      find.byType(CircularProgressIndicator),
    );
    expect(indicator.value, 0.42);
    expect(find.text('42%'), findsOneWidget);
  });
}
