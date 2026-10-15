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
      if (call.method == 'Clipboard.setData')
        copied = call.arguments['text'] as String;
      return null;
    });
  });
  tearDown(() => TestDefaultBinaryMessengerBinding
      .instance.defaultBinaryMessenger
      .setMockMethodCallHandler(SystemChannels.platform, null));

  for (final brightness in Brightness.values) {
    testWidgets('visible hover tooltip changes on copy and resets: $brightness',
        (tester) async {
      await tester.pumpWidget(MaterialApp(
          theme: ThemeData(brightness: brightness),
          home: const Scaffold(
              body: Center(child: CopyButton(value: 'ABC123')))));
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

  testWidgets(
      'public form link copies server-confirmed baseline and fits narrow layout',
      (tester) async {
    Widget app(String link, {String? savedLink}) => MaterialApp(
        home: Scaffold(
            body: SizedBox(
                width: 220,
                child: FormPublicLink(link: link, savedLink: savedLink))));
    await tester.pumpWidget(app('long-form-identifier-1234567890',
        savedLink: 'long-form-identifier-1234567890'));
    await tester.tap(find.byType(CopyButton));
    await tester.pumpAndSettle();
    expect(copied, '${AppConfig.webLink}/form/long-form-identifier-1234567890');
    expect(find.text(CommonStrings.copied), findsOneWidget);
    // Typing or a rejected save must never make the draft copyable.
    await tester.pumpWidget(
        app('unsaved', savedLink: 'long-form-identifier-1234567890'));
    await tester.pumpAndSettle();
    await tester.tap(find.byType(CopyButton));
    expect(copied, '${AppConfig.webLink}/form/long-form-identifier-1234567890');
    // A successful response replaces the saved baseline.
    await tester.pumpWidget(app('renamed', savedLink: 'renamed'));
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
  testWidgets('new form and occasion drafts expose no copy action',
      (tester) async {
    for (final isForm in [true, false]) {
      for (final draft in ['', 'manual-slug']) {
        await tester.pumpWidget(MaterialApp(
            home: Scaffold(body: PublicLink(link: draft, isForm: isForm))));
        expect(find.byType(CopyButton), findsNothing);
      }
    }
  });

  test('new public slug format has narrow ASCII and length boundaries', () {
    for (final value in ['abc', 'summer-2027', 'a' * 80]) {
      expect(isValidPublicSlug(value), isTrue);
    }
    for (final value in [
      '',
      'Upper',
      'under_score',
      '-edge',
      'edge-',
      'two--hyphens',
      'á',
      'spaces here',
      'a' * 81
    ]) {
      expect(isValidPublicSlug(value), isFalse);
    }
    expect(isValidPublicSlug('', allowEmpty: true), isTrue);
  });
}
