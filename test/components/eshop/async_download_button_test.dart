import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:fstapp/components/_shared/async_download_button.dart';
import 'package:fstapp/widgets/dependency_material_bridge.dart';

import '../../support/fixtures/widget_environment_fixture.dart';

void main() {
  WidgetEnvironmentFixture.register();
  for (final iconOnly in [false, true]) {
    testWidgets(
      'download is single flight and recovers after completion, iconOnly=$iconOnly',
      (tester) async {
        var calls = 0;
        var pending = Completer<void>();
        final env = WidgetEnvironmentFixture(
          locale: const Locale('en'),
          translations: jsonDecode(
            File('assets/translations/en.json').readAsStringSync(),
          ),
        );
        await env.pumpWidget(
          tester,
          MaterialApp(
            builder: DependencyMaterialBridge.builder,
            home: Scaffold(
              body: AsyncDownloadButton(
                label: 'Download PDF',
                loadingLabel: 'Generating PDF',
                iconOnly: iconOnly,
                onDownload: () {
                  calls++;
                  return pending.future;
                },
              ),
            ),
          ),
        );
        final button = iconOnly
            ? find.byType(IconButton)
            : find.byType(TextButton);
        final action = iconOnly
            ? tester.widget<IconButton>(button).onPressed!
            : tester.widget<TextButton>(button).onPressed!;
        // Even callbacks queued before the disabled frame cannot start twice.
        action();
        action();
        await tester.pump();
        expect(calls, 1);
        expect(find.byType(CircularProgressIndicator), findsOneWidget);
        if (iconOnly) {
          expect(tester.widget<IconButton>(button).onPressed, isNull);
          expect(tester.widget<IconButton>(button).tooltip, 'Generating PDF');
        } else {
          expect(tester.widget<TextButton>(button).onPressed, isNull);
          expect(find.text('Generating PDF'), findsOneWidget);
        }
        pending.complete();
        await tester.pumpAndSettle();
        expect(find.byType(CircularProgressIndicator), findsNothing);
        pending = Completer<void>();
        await tester.tap(button);
        await tester.pump();
        expect(calls, 2);
        await tester.pumpWidget(const SizedBox.shrink());
        pending.complete();
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
      },
    );
  }

  testWidgets('failed download releases the button for retry', (tester) async {
    var fail = true;
    final env = WidgetEnvironmentFixture(
      locale: const Locale('en'),
      translations: jsonDecode(
        File('assets/translations/en.json').readAsStringSync(),
      ),
    );
    await env.pumpWidget(
      tester,
      MaterialApp(
        builder: DependencyMaterialBridge.builder,
        home: Scaffold(
          body: AsyncDownloadButton(
            label: 'Download PDF',
            loadingLabel: 'Generating PDF',
            onDownload: () async {
              if (fail) throw StateError('Test generation failed');
            },
          ),
        ),
      ),
    );
    await tester.tap(find.byType(TextButton));
    await tester.pumpAndSettle();
    expect(
      tester.widget<TextButton>(find.byType(TextButton)).onPressed,
      isNotNull,
    );
    expect(find.byType(CircularProgressIndicator), findsNothing);
    fail = false;
    await tester.tap(find.byType(TextButton));
    await tester.pumpAndSettle();
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(seconds: 5));
    expect(tester.takeException(), isNull);
  });
}
