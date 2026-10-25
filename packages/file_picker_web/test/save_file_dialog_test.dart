@TestOn('browser')
library;

import 'dart:convert';
import 'dart:js_interop';
import 'dart:js_interop_unsafe';
import 'dart:typed_data';

import 'package:file_picker_platform_interface/file_picker_platform_interface.dart';
import 'package:file_picker_web/file_picker_web.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_web_plugins/flutter_web_plugins.dart';

void main() {
  final bytes = Uint8List.fromList(utf8.encode('hello'));

  void runJs(String code) => globalContext.callMethod('eval'.toJS, code.toJS);

  JSAny? readJs(String expression) =>
      globalContext.callMethod('eval'.toJS, expression.toJS);

  late final FilePickerWeb picker;

  setUpAll(() {
    FilePickerWeb.registerWith(webPluginRegistrar);
    picker = FilePickerPlatform.instance as FilePickerWeb;
    runJs('''
      window.__originalSaveFilePicker = window.showSaveFilePicker;
      window.__originalAnchorClick = HTMLAnchorElement.prototype.click;
    ''');
  });

  setUp(() {
    // Record downloads instead of triggering them.
    runJs('''
      window.__downloads = [];
      window.__pickerCalls = [];
      window.__written = [];
      HTMLAnchorElement.prototype.click = function () {
        window.__downloads.push(this.download);
      };
    ''');
  });

  tearDownAll(() {
    runJs('''
      window.showSaveFilePicker = window.__originalSaveFilePicker;
      HTMLAnchorElement.prototype.click = window.__originalAnchorClick;
    ''');
  });

  /// Replaces `showSaveFilePicker` with [body], an async JS function body
  /// that receives `options`.
  void stubPicker(String body) {
    runJs('''
      window.showSaveFilePicker = async (options) => {
        window.__pickerCalls.push(options);
        $body
      };
    ''');
  }

  Future<Uri?> save({WebSaveFileMode? saveMode}) {
    return picker.saveFile(
      fileName: 'report.txt',
      bytes: bytes,
      mimeType: 'text/plain',
      webOptions: saveMode == null
          ? const WebOptions()
          : FilePickerWebOptions(saveMode: saveMode),
    );
  }

  List<String> downloads() => [
    for (final name
        in (readJs('window.__downloads') as JSArray<JSString>).toDart)
      name.toDart,
  ];

  int pickerCalls() =>
      (readJs('window.__pickerCalls.length') as JSNumber).toDartInt;

  test('saves through the dialog and returns the chosen name', () async {
    stubPicker('''
      return {
        name: 'chosen.txt',
        createWritable: async () => ({
          write: async (data) => { window.__written.push(data); },
          close: async () => {},
        }),
      };
    ''');

    final uri = await save(saveMode: WebSaveFileMode.dialog);

    expect(uri, Uri(path: 'chosen.txt'));
    expect(uri!.scheme, isEmpty);
    expect(uri.hasAuthority, isFalse);
    expect(uri.hasQuery, isFalse);
    expect(uri.hasFragment, isFalse);
    expect(downloads(), isEmpty);
    final written = readJs('window.__written[0]') as JSUint8Array;
    expect(utf8.decode(written.toDart), 'hello');
    expect(
      (readJs('window.__pickerCalls[0].suggestedName') as JSString).toDart,
      'report.txt',
    );
    expect(
      (readJs('window.__pickerCalls[0].types[0].accept["text/plain"][0]')
              as JSString)
          .toDart,
      '.txt',
    );
  });

  test('returns null without downloading when the user cancels', () async {
    stubPicker("throw new DOMException('cancelled', 'AbortError');");

    expect(await save(saveMode: WebSaveFileMode.dialog), isNull);
    expect(pickerCalls(), 1);
    expect(downloads(), isEmpty);
  });

  test(
    'falls back to a download when the browser refuses the dialog',
    () async {
      stubPicker("throw new DOMException('no gesture', 'SecurityError');");

      expect(await save(saveMode: WebSaveFileMode.dialog), isNull);
      expect(pickerCalls(), 1);
      expect(downloads(), ['report.txt']);
    },
  );

  test('throws without downloading when the dialog is not supported', () async {
    runJs('delete window.showSaveFilePicker;');

    expect(supportsShowSaveFileDialog, isFalse);
    await expectLater(
      save(saveMode: WebSaveFileMode.dialog),
      throwsUnsupportedError,
    );
    expect(downloads(), isEmpty);
  });

  test('reports support when the dialog is available', () {
    stubPicker('return null;');

    expect(supportsShowSaveFileDialog, isTrue);
  });

  test('downloads without opening the dialog by default', () async {
    stubPicker('throw new Error("should not be called");');

    expect(await save(), isNull);
    expect(await save(saveMode: WebSaveFileMode.download), isNull);
    expect(pickerCalls(), 0);
    expect(downloads(), ['report.txt', 'report.txt']);
  });
}
