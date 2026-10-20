import 'dart:js_interop';

@JS('window')
external _Window get _window;
extension type _Window(JSObject _) implements JSObject {
  external void addEventListener(String type, JSFunction listener);
  external void removeEventListener(String type, JSFunction listener);
}
extension type _Event(JSObject _) implements JSObject {
  external double get clientX;
  external double get clientY;
  external void preventDefault();
}

/// Suppress the browser menu only inside an editor canvas with custom actions.
void Function() suppressCanvasContextMenu(
  bool Function(double, double) contains,
) {
  final listener = ((_Event event) {
    if (contains(event.clientX, event.clientY)) event.preventDefault();
  }).toJS;
  _window.addEventListener('contextmenu', listener);
  return () => _window.removeEventListener('contextmenu', listener);
}
