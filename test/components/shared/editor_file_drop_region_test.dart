import 'package:fstapp/services/import_file.dart';
import 'package:fstapp/services/dialog_helper.dart';
import 'package:fstapp/widgets/drop_file.dart';
import 'package:fstapp/widgets/dependency_material_bridge.dart';
import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:material_ui/material_ui.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fstapp/components/_shared/editor_file_drop_region.dart';
import 'package:fstapp/components/_shared/editor_file_drop_strings.dart';
import '../../support/editor_file_drop.dart';
import '../../support/fixtures/widget_environment_fixture.dart';

late WidgetEnvironmentFixture environment;

void main() {
  WidgetEnvironmentFixture.register();
  setUpAll(() {
    environment = WidgetEnvironmentFixture(
        locale: const Locale('cs'),
        translations:
            jsonDecode(File('assets/translations/cs.json').readAsStringSync())
                as Map<String, dynamic>);
  });
  setUp(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
            const MethodChannel('PonnamKarthik/fluttertoast'),
            (_) async => true);
  });
  test('a failed provider read is never replaced by empty content', () async {
    final file = ImportFile(name: 'failed.csv',
        readBytes: () async => throw PlatformException(code: 'source_expired'));
    await expectLater(file.retain(), throwsA(isA<PlatformException>()));
    await expectLater(file.readAsBytes(), throwsA(isA<PlatformException>()));
  });

  test('retained content keeps bytes, name, MIME and length after provider expiry', () async {
    var alive = true;
    var reads = 0;
    final bytes = Uint8List.fromList(utf8.encode('Jméno;příjmení\nJan;Novák'));
    final file = ImportFile(name: 'Příloha #1.csv', mimeType: 'text/csv',
        readBytes: () async { if (!alive) throw StateError('expired'); reads++; return bytes; },
        size: () async { if (!alive) throw StateError('expired'); return bytes.length; });
    expect(reads, 0);
    await file.retain();
    alive = false;
    expect(await file.readAsBytes(), bytes);
    expect(await file.readAsString(), 'Jméno;příjmení\nJan;Novák');
    expect(await file.length(), bytes.length);
    expect(file.name, 'Příloha #1.csv');
    expect(file.mimeType, 'text/csv');
    expect(reads, 1);
  });

  testWidgetsWithEnvironment(() => environment,
      'directory drop keeps nested file names and bytes while rejecting other extensions',
      (tester) async {
    ImportFile? received;
    await environment.pumpWidget(tester, MaterialApp(
        builder: DependencyMaterialBridge.builder,
        home: Scaffold(body: DropFile(allowedExtensions: ['csv'],
            onFilePathChanged: (file) async { received = await file.retain(); }))));
    final data = utf8.encode('číslo;hodnota\n01;příloha');
    final folder = droppedFile('folder', [], directory: true);
    folder['children'] = [droppedFile('ignore.txt', [1]),
      {...droppedFile('nested', [], directory: true),
        'children': [droppedFile('příloha.csv', data)]}];
    await pluginDrop(tester, tester.getCenter(find.byType(DropFile)), [folder]);
    await tester.pumpAndSettle();
    expect(received!.name, 'příloha.csv');
    expect(await received!.readAsBytes(), data);
    expect(await received!.readAsString(), 'číslo;hodnota\n01;příloha');
  });

  testWidgetsWithEnvironment(() => environment,
      'CSV confirmation retains dropped bytes after provider completion', (tester) async {
    final result = Completer<ImportFile?>();
    await environment.pumpWidget(tester, MaterialApp(
        builder: DependencyMaterialBridge.builder,
        home: Scaffold(body: TextButton(onPressed: () async {
          result.complete(await DialogHelper.dropFilesHere(
              tester.element(find.byType(TextButton)), 'CSV', 'Import', 'Cancel',
              allowedExtensions: ['csv']));
        }, child: const Text('Choose')))));
    await tester.tap(find.text('Choose'));
    await tester.pumpAndSettle();
    final contents = utf8.encode('Jméno;příjmení\nJan;Novák');
    final read = Completer<void>();
    await pluginDrop(tester, tester.getCenter(find.byType(DropFile)),
        [droppedFile('Příloha.csv', contents)], beforeRead: read.future);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Import'));
    await tester.pumpAndSettle();
    expect(result.isCompleted, isFalse, reason: 'Confirmation must await pending provider data');
    read.complete();
    await tester.pumpAndSettle();
    final file = await result.future.timeout(const Duration(seconds: 3));
    expect(file!.name, 'Příloha.csv');
    expect(await file.readAsBytes(), contents);
    expect(await file.readAsString(), 'Jméno;příjmení\nJan;Novák');
    expect(await file.length(), contents.length);
  });

  testWidgetsWithEnvironment(() => environment,
      'plugin accepts one file once, rejects directories/types/batches and locks pending import',
      (tester) async {
    var calls = 0;
    var enabled = true;
    var active = true;
    var pending = Completer<void>();
    late StateSetter update;
    await environment.pumpWidget(tester,
        MaterialApp(builder: DependencyMaterialBridge.builder, home: StatefulBuilder(builder: (context, setState) {
      update = setState;
      return Scaffold(
          body: EditorFileDropRegion(
              enabled: enabled,
              active: active,
              hint: EditorFileDropStrings.hint,
              allowedExtensions: editorRasterExtensions,
              onFileDropped: (_) async {
                calls++;
                try {
                  await pending.future;
                } catch (_) {}
              },
              child: const SizedBox.expand()));
    })));
    await tester.pumpAndSettle();
    final point = tester.getCenter(find.byType(EditorFileDropRegion));
    final file = droppedFile('image.png', [1]);
    for (final files in [
      <Map<String, Object?>>[],
      [file, file],
      [droppedFile('dir.png', [], directory: true)],
      [
        droppedFile('image.svg', [1])
      ]
    ]) {
      await pluginDrop(tester, point, files);
    }
    expect(calls, 0);
    update(() => enabled = false);
    await tester.pump();
    await pluginDrop(tester, point, [file]);
    update(() {
      enabled = true;
      active = false;
    });
    await tester.pump();
    await pluginDrop(tester, point, [file]);
    expect(calls, 0);
    update(() => active = true);
    await tester.pump();
    await pluginDrop(tester, point, [file]);
    await pluginDrop(tester, point, [file]);
    expect(calls, 1);
    pending.completeError(StateError('host upload failed'));
    await tester.pumpAndSettle();
    // Host handles a failed import; completing it always releases the drop lock.
    pending = Completer<void>()..complete();
    await pluginDrop(tester, point, [file]);
    await tester.pumpAndSettle();
    expect(calls, 2);
    await tester.pump(const Duration(seconds: 4));
  });
  testWidgetsWithEnvironment(() => environment,
      'root modal and inactive retained nested route reject drops',
      (tester) async {
    var calls = 0;
    var active = true;
    late BuildContext rootContext;
    late StateSetter update;
    await environment.pumpWidget(tester,
        MaterialApp(builder: DependencyMaterialBridge.builder, home: Builder(builder: (context) {
      rootContext = context;
      return StatefulBuilder(builder: (context, setState) {
        update = setState;
        return TickerMode(
            enabled: active,
            child: Navigator(
                onGenerateRoute: (_) => MaterialPageRoute<void>(
                    builder: (_) => Scaffold(
                        body: EditorFileDropRegion(
                            enabled: true,
                            active: true,
                            hint: 'drop',
                            allowedExtensions: editorRasterExtensions,
                            onFileDropped: (_) async {
                              calls++;
                            },
                            child: const SizedBox.expand())))));
      });
    })));
    await tester.pumpAndSettle();
    final point = tester.getCenter(find.byType(EditorFileDropRegion));
    final file = droppedFile('image.png', [1]);
    showDialog<void>(
        context: rootContext,
        builder: (_) => const AlertDialog(content: Text('modal')));
    await tester.pumpAndSettle();
    await pluginDrop(tester, point, [file]);
    expect(calls, 0);
    Navigator.of(rootContext).pop();
    await tester.pumpAndSettle();
    update(() => active = false);
    await tester.pumpAndSettle();
    await pluginDrop(tester, point, [file]);
    expect(calls, 0);
    update(() => active = true);
    await tester.pumpAndSettle();
    await pluginDrop(tester, point, [file]);
    await tester.pumpAndSettle();
    expect(calls, 1);
  });
}
