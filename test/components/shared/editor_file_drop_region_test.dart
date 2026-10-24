import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
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
  testWidgetsWithEnvironment(() => environment,
      'plugin accepts one file once, rejects directories/types/batches and locks pending import',
      (tester) async {
    var calls = 0;
    var enabled = true;
    var active = true;
    var pending = Completer<void>();
    late StateSetter update;
    await environment.pumpWidget(tester,
        MaterialApp(home: StatefulBuilder(builder: (context, setState) {
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
        MaterialApp(home: Builder(builder: (context) {
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
