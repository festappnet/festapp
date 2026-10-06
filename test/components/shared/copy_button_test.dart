import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fstapp/app_config.dart';
import 'package:fstapp/components/_shared/common_strings.dart';
import 'package:fstapp/components/_shared/copy_button.dart';
import 'package:fstapp/components/forms/views/form_public_link.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  String? copied;
  setUp(() {
    copied = null;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, (call) async {
      if (call.method == 'Clipboard.setData') copied = call.arguments['text'] as String;
      return null;
    });
  });
  tearDown(() => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      .setMockMethodCallHandler(SystemChannels.platform, null));

  for (final brightness in Brightness.values) {
    testWidgets('visible hover tooltip changes on copy and resets: $brightness', (tester) async {
      await tester.pumpWidget(MaterialApp(theme: ThemeData(brightness: brightness),
          home: const Scaffold(body: Center(child: CopyButton(value: 'ABC123')))));
      final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
      await mouse.addPointer(location: Offset.zero);
      await mouse.moveTo(tester.getCenter(find.byType(IconButton)));
      await tester.pumpAndSettle();
      expect(find.text(CommonStrings.copy), findsOneWidget);
      await tester.tap(find.byType(IconButton));
      await tester.pumpAndSettle();
      expect(copied, 'ABC123');
      expect(find.text(CommonStrings.copied), findsOneWidget);
      expect(find.text(CommonStrings.copy), findsNothing);
      expect(find.byIcon(Icons.check), findsOneWidget);
      await tester.pump(const Duration(seconds: 2));
      await tester.pumpAndSettle();
      expect(find.byIcon(Icons.copy), findsOneWidget);
      expect(find.text(CommonStrings.copied), findsNothing);
      await mouse.removePointer();
    });
  }

  testWidgets('public form link copies full URL, follows edits and fits narrow layout', (tester) async {
    Widget app(String link) => MaterialApp(home: Scaffold(body: SizedBox(width: 220,
        child: FormPublicLink(link: link))));
    await tester.pumpWidget(app('long-form-identifier-1234567890'));
    await tester.tap(find.byType(CopyButton));
    await tester.pumpAndSettle();
    expect(copied, '${AppConfig.webLink}/form/long-form-identifier-1234567890');
    expect(find.text(CommonStrings.copied), findsOneWidget);
    await tester.pumpWidget(app('renamed'));
    await tester.pumpAndSettle();
    expect(find.byIcon(Icons.copy), findsOneWidget);
    expect(find.text(CommonStrings.copied), findsNothing);
    await tester.tap(find.byType(CopyButton));
    await tester.pumpAndSettle();
    expect(copied, '${AppConfig.webLink}/form/renamed');
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(seconds: 3));
    expect(tester.takeException(), isNull);
  });
}
