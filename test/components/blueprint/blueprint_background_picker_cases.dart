import 'package:fstapp/widgets/dependency_material_bridge.dart';

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:fstapp/services/import_file.dart';

import '../../support/editor_file_drop.dart';

import 'package:material_ui/material_ui.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fstapp/components/blueprint/views/blueprint_layout_background.dart';
import 'package:fstapp/widgets/drop_file.dart';

import '../../support/fixtures/widget_environment_fixture.dart';

void main() {
  test('graphic recognition preserves SVG with a long authoring prefix and sniffs bitmap signatures', () {
    final source =
        '<!--${'original ' * 500}--><svg xmlns="http://www.w3.org/2000/svg" width="100" height="50"><rect width="100" height="50"/></svg>';
    expect(
      blueprintGraphicFormat(Uint8List.fromList(utf8.encode(source))).name,
      'svg',
    );
    expect(
      blueprintGraphicFormat(Uint8List.fromList([0xff, 0xd8, 0xff, 0x00])).name,
      'jpeg',
    );
    expect(
      () => blueprintGraphicFormat(Uint8List.fromList([0x00, 0x01, 0x02])),
      throwsFormatException,
    );
  });

  WidgetEnvironmentFixture.register();
  late WidgetEnvironmentFixture environment;
  setUpAll(() {
    environment = WidgetEnvironmentFixture(
      locale: const Locale('cs'),
      translations: jsonDecode(
        File('assets/translations/cs.json').readAsStringSync(),
      ) as Map<String, dynamic>,
    );
  });

  Future<void> open(
    WidgetTester tester,
    Future<ImportFile?> Function() picker,
    void Function(ImportFile?) complete, {
    bool graphic = false,
  }) async {
    await environment.pumpWidget(
      tester,
      MaterialApp(
        builder: DependencyMaterialBridge.builder,
        home: Builder(
          builder: (context) => Scaffold(
            body: TextButton(
              onPressed: () async => complete(
                await showBlueprintBackgroundPicker(
                  context,
                  pickFile: picker,
                  graphic: graphic,
                ),
              ),
              child: const Text('Open background'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Open background'));
    await tester.pumpAndSettle();
  }

  testWidgetsWithEnvironment(
    () => environment,
    'background opens a drop dialog before any picker and cancelling selects nothing',
    (tester) async {
      var picks = 0;
      var completed = false;
      await open(
        tester,
        () async {
          picks++;
          return null;
        },
        (file) {
          completed = true;
          expect(file, isNull);
        },
      );
      expect(
        find.byKey(const ValueKey('blueprint-background-picker')),
        findsOneWidget,
      );
      expect(find.byType(DropFile), findsOneWidget);
      expect(tester.widget<DropFile>(find.byType(DropFile)).allowedExtensions, [
        'png',
        'jpg',
        'jpeg',
        'webp',
        'gif',
        'svg',
      ]);
      expect(picks, 0);
      expect(
        find.descendant(
          of: find.byKey(const ValueKey('blueprint-background-picker')),
          matching: find.byType(TextButton),
        ),
        findsNothing,
      );
      await tester.tap(find.byIcon(Icons.close));
      await tester.pumpAndSettle();
      expect(completed, isTrue);
      expect(picks, 0);
    },
  );

  testWidgetsWithEnvironment(
    () => environment,
    'waiting for or cancelling the system picker keeps selection idle',
    (tester) async {
      final pending = Completer<ImportFile?>();
      var completed = false;
      await open(tester, () => pending.future, (_) => completed = true);
      await tester.tap(
        find.descendant(
          of: find.byType(DropFile),
          matching: find.byType(InkWell),
        ),
      );
      await tester.pump();
      expect(completed, isFalse);
      expect(find.byType(LinearProgressIndicator), findsNothing);
      pending.complete(null);
      await tester.pumpAndSettle();
      expect(completed, isFalse);
      expect(find.byType(DropFile), findsOneWidget);
      expect(find.byType(LinearProgressIndicator), findsNothing);
      await tester.tap(find.byIcon(Icons.close));
      await tester.pumpAndSettle();
      expect(completed, isTrue);
    },
  );

  testWidgetsWithEnvironment(
    () => environment,
    'clicking the drop area invokes the picker and returns selected bytes',
    (tester) async {
      var picks = 0;
      ImportFile? result;
      final file = ImportFile.fromData(
        Uint8List.fromList([1, 2, 3]),
        name: 'plan.png',
      );
      await open(tester, () async {
        picks++;
        return file;
      }, (value) => result = value);
      await tester.tap(
        find.descendant(
          of: find.byType(DropFile),
          matching: find.byType(InkWell),
        ),
      );
      await tester.pumpAndSettle();
      expect(picks, 1);
      expect(result, same(file));
      expect(await result!.readAsBytes(), [1, 2, 3]);
      expect(
        find.byKey(const ValueKey('blueprint-background-picker')),
        findsNothing,
      );
    },
  );

  testWidgetsWithEnvironment(
    () => environment,
    'dropping an allowed image selects it without opening the system picker',
    (tester) async {
      var picks = 0;
      ImportFile? result;
      await open(
        tester,
        () async {
          picks++;
          return null;
        },
        (value) => result = value,
        graphic: true,
      );
      final point = tester.getCenter(find.byType(DropFile));
      await pluginDrop(tester, point, [droppedFile('notes.txt', [])]);
      expect(find.byType(DropFile), findsOneWidget);
      final svgBytes = utf8.encode('<svg/>');
      await pluginDrop(tester, point, [droppedFile('plan.svg', svgBytes)]);
      await tester.pumpAndSettle();
      expect(result!.name, 'plan.svg');
      expect(await result!.readAsBytes(), svgBytes);
      expect(picks, 0);
      expect(
        find.byKey(const ValueKey('blueprint-background-picker')),
        findsNothing,
      );
    },
  );
}
