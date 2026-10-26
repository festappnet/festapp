import 'dart:js_interop';
import 'dart:typed_data';

import 'package:path/path.dart' as p;
import 'package:web/web.dart';

// `showSaveFilePicker()` is not part of package:web, since it is an experimental API.
//
// See https://developer.mozilla.org/en-US/docs/Web/API/Window/showSaveFilePicker#browser_compatibility
@JS('showSaveFilePicker')
external JSFunction? get _showSaveFilePickerFunction;

/// Whether the browser supports the `showSaveFilePicker` API.
bool get supportsShowSaveFileDialog => _showSaveFilePickerFunction != null;

@JS('showSaveFilePicker')
external JSPromise<FileSystemFileHandle> _showSaveFilePicker(
  _SaveFilePickerOptions options,
);

extension type _SaveFilePickerOptions._(JSObject _) implements JSObject {
  external factory _SaveFilePickerOptions({
    String suggestedName,
    JSArray<_FilePickerAcceptType> types,
  });
}

extension type _FilePickerAcceptType._(JSObject _) implements JSObject {
  external factory _FilePickerAcceptType({JSAny accept});
}

/// The outcome of [saveWithDialog].
///
/// [shown] is `false` when the browser refused to open the dialog, so the
/// caller should fall back to a download. When it was shown, [name] is the file name
/// the user saved to, or `null` if they cancelled.
typedef SaveDialogResult = ({bool shown, String? name});

/// Saves [bytes] through the browser's save dialog, prefilled with
/// [fileName] and an accepted type built from [mimeType] and the file's
/// extension.
///
/// Throws an [UnsupportedError] if the browser does not support the dialog.
/// Errors while writing the chosen file are thrown, since the user already
/// picked a destination.
Future<SaveDialogResult> saveWithDialog({
  required String fileName,
  required Uint8List bytes,
  required String mimeType,
}) async {
  if (!supportsShowSaveFileDialog) {
    throw UnsupportedError(
      'This browser does not support the showSaveFilePicker API.',
    );
  }

  final FileSystemFileHandle handle;
  try {
    handle = await _showSaveFilePicker(
      _SaveFilePickerOptions(
        suggestedName: fileName,
        types: [
          _FilePickerAcceptType(
            accept: {
              mimeType: [p.extension(fileName)],
            }.jsify()!,
          ),
        ].toJS,
      ),
    ).toDart;
  } catch (e) {
    if (e case DOMException(name: 'AbortError')) {
      return (shown: true, name: null);
    }
    // The browser refused to open it, typically because there was no recent
    // user gesture.
    return (shown: false, name: null);
  }

  final writable = await handle.createWritable().toDart;
  await writable.write(bytes.toJS).toDart;
  await writable.close().toDart;
  return (shown: true, name: handle.name);
}
