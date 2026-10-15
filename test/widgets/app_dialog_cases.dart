import '../support/fixtures/localization_log_fixture.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fstapp/widgets/app_dialog.dart';
import 'package:fstapp/theme_config.dart';

Future<void> openDialog(WidgetTester tester, WidgetBuilder builder,
    {ValueChanged<String?>? onResult}) async {
  await tester.pumpWidget(MaterialApp(
    home: Scaffold(
      body: Builder(
        builder: (context) => TextButton(
          onPressed: () async {
            final result = await showDialog<String>(
                context: context, barrierDismissible: false, builder: builder);
            onResult?.call(result);
          },
          child: const Text('Open'),
        ),
      ),
    ),
  ));
  await tester.tap(find.text('Open'));
  await tester.pumpAndSettle();
}

void main() {
  // This suite intentionally uses untranslated key fallback (no catalog).
  setUp(() {
    final logs = LocalizationLogFixture.install(expectedMissingCatalog: true);
    addTearDown(logs.dispose);
  });
  test('light and dark themes share the shape with native modal pickers', () {
    for (final brightness in Brightness.values) {
      final theme = ThemeConfig.theme(brightness: brightness);
      expect(theme.dialogTheme.shape, appDialogShape);
      expect(theme.datePickerTheme.shape, appDialogShape);
      expect(theme.timePickerTheme.shape, appDialogShape);
      expect(theme.bottomSheetTheme.shape, appDialogShape);
    }
  });

  testWidgets('Escape works before input focus', (tester) async {
    var closed = false;
    await openDialog(
        tester, (_) => AppAlertDialog(title: const Text('Settings')),
        onResult: (_) => closed = true);
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();
    expect(closed, isTrue);
    expect(find.byType(AppAlertDialog), findsNothing);
  });

  testWidgets('Escape and the header close preserve the same result',
      (tester) async {
    for (final escape in [true, false]) {
      String? result;
      await openDialog(
        tester,
        (context) => AppAlertDialog(
          title: const Text('Settings'),
          onClose: () => Navigator.pop(context, 'cancel'),
        ),
        onResult: (value) => result = value,
      );
      if (escape) {
        await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      } else {
        await tester.tap(find.byIcon(Icons.close));
      }
      await tester.pumpAndSettle();
      expect(result, 'cancel');
    }
  });

  testWidgets('default dismissal respects a draft PopScope', (tester) async {
    var attempts = 0;
    await openDialog(
      tester,
      (_) => PopScope(
        canPop: false,
        onPopInvokedWithResult: (didPop, _) {
          if (!didPop) attempts++;
        },
        child: AppAlertDialog(title: const Text('Draft')),
      ),
    );
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();
    await tester.tap(find.byIcon(Icons.close));
    await tester.pumpAndSettle();
    expect(attempts, 2);
    expect(find.byType(AppAlertDialog), findsOneWidget);
  });

  testWidgets('blocking progress cannot be dismissed with Escape or close',
      (tester) async {
    await openDialog(
        tester,
        (_) =>
            AppAlertDialog(dismissible: false, title: const Text('Working')));
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();
    expect(find.byType(AppAlertDialog), findsOneWidget);
    expect(
        tester.widget<IconButton>(find.byType(IconButton)).onPressed, isNull);
  });

  for (final width in [320.0, 1200.0]) {
    testWidgets('full-page header keeps close right at width $width',
        (tester) async {
      tester.view.physicalSize = Size(width, 800);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await openDialog(
        tester,
        (_) => AppDialog.fullscreen(
          child: Scaffold(
            appBar: AppDialogAppBar(
              title: const Text('Description'),
              actions: [
                IconButton(
                    onPressed: () {}, icon: const Icon(Icons.open_in_full)),
              ],
            ),
            body: const Text('Content'),
          ),
        ),
      );
      expect(tester.getCenter(find.byIcon(Icons.close)).dx,
          greaterThan(tester.getCenter(find.byIcon(Icons.open_in_full)).dx));
      expect(find.byType(BackButton), findsNothing);
      expect(tester.takeException(), isNull);
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pumpAndSettle();
      expect(find.byType(AppDialog), findsNothing);
    });
  }
}
