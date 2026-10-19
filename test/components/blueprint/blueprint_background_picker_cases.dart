import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:cross_file/cross_file.dart';
import 'package:desktop_drop/desktop_drop.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fstapp/components/_shared/common_strings.dart';
import 'package:fstapp/components/blueprint/views/blueprint_layout_background.dart';
import 'package:fstapp/widgets/drop_file.dart';
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

  Future<void> open(WidgetTester tester, Future<XFile?> Function() picker,
      void Function(XFile?) complete) async {
    await environment.pumpWidget(
        tester,
        MaterialApp(
            home: Builder(
          builder: (context) => Scaffold(
              body: TextButton(
            onPressed: () async => complete(
                await showBlueprintBackgroundPicker(context, pickFile: picker)),
            child: const Text('Open background'),
          )),
        )));
    await tester.tap(find.text('Open background'));
    await tester.pumpAndSettle();
  }

  testWidgetsWithEnvironment(() => environment,
      'background opens a drop dialog before any picker and cancelling selects nothing',
      (tester) async {
    var picks = 0;
    var completed = false;
    await open(tester, () async {
      picks++;
      return null;
    }, (file) {
      completed = true;
      expect(file, isNull);
    });
    expect(find.byKey(const ValueKey('blueprint-background-picker')),
        findsOneWidget);
    expect(find.byType(DropFile), findsOneWidget);
    expect(tester.widget<DropFile>(find.byType(DropFile)).allowedExtensions,
        ['png', 'jpg', 'jpeg', 'webp', 'svg']);
    expect(picks, 0);
    await tester.tap(find.widgetWithText(TextButton, CommonStrings.cancel));
    await tester.pumpAndSettle();
    expect(completed, isTrue);
    expect(picks, 0);
  });

  testWidgetsWithEnvironment(() => environment,
      'clicking the drop area invokes the picker and returns selected bytes',
      (tester) async {
    var picks = 0;
    XFile? result;
    final file =
        XFile.fromData(Uint8List.fromList([1, 2, 3]), name: 'plan.png');
    await open(tester, () async {
      picks++;
      return file;
    }, (value) => result = value);
    await tester.tap(find.descendant(
        of: find.byType(DropFile), matching: find.byType(InkWell)));
    await tester.pumpAndSettle();
    expect(picks, 1);
    expect(result, same(file));
    expect(await result!.readAsBytes(), [1, 2, 3]);
    expect(find.byKey(const ValueKey('blueprint-background-picker')),
        findsNothing);
  });

  testWidgetsWithEnvironment(() => environment,
      'dropping an allowed image selects it without opening the system picker',
      (tester) async {
    var picks = 0;
    XFile? result;
    await open(tester, () async {
      picks++;
      return null;
    }, (value) => result = value);
    final target = tester.widget<DropTarget>(find.byType(DropTarget));
    target.onDragDone!(DropDoneDetails(
        files: [DropItemFile.fromData(Uint8List(0), name: 'notes.txt', path: '/fixture/notes.txt')],
        localPosition: Offset.zero,
        globalPosition: Offset.zero));
    await tester.pump();
    expect(find.byType(DropFile), findsOneWidget);
    final svg = DropItemFile.fromData(Uint8List.fromList(utf8.encode('<svg/>')),
        name: 'plan.svg', path: '/fixture/plan.svg', mimeType: 'image/svg+xml');
    target.onDragDone!(DropDoneDetails(
        files: [svg], localPosition: Offset.zero, globalPosition: Offset.zero));
    await tester.pumpAndSettle();
    expect(result, same(svg));
    expect(picks, 0);
    expect(find.byKey(const ValueKey('blueprint-background-picker')),
        findsNothing);
  });
}
