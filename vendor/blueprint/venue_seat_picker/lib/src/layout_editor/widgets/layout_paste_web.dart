import 'dart:js_interop';

const usesNativePasteEvents = true;

@JS('window')
external _PasteWindow get _window;

extension type _PasteWindow(JSObject _) implements JSObject {
  external void addEventListener(String type, JSFunction listener);
  external void removeEventListener(String type, JSFunction listener);
}

extension type _PasteEvent(JSObject _) implements JSObject {
  external _PasteData? get clipboardData;
  external void preventDefault();
}

extension type _PasteData(JSObject _) implements JSObject {
  external String getData(String type);
}

/// Reads only data delivered by an actual user paste gesture. No permission
/// request or asynchronous clipboard read is involved.
void Function() listenForLayoutPaste(bool Function(String) accept) {
  final listener = ((_PasteEvent event) {
    final text = event.clipboardData?.getData('text/plain');
    if (text != null && text.isNotEmpty && accept(text)) {
      event.preventDefault();
    }
  }).toJS;
  _window.addEventListener('paste', listener);
  return () => _window.removeEventListener('paste', listener);
}
