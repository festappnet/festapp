import 'dart:async';

class JSInterop {
  static final JSInterop _instance = JSInterop._internal();
  factory JSInterop() => _instance;
  JSInterop._internal();

  /// Stub for the popstate event stream.
  /// Returns an empty stream on non-web platforms.
  Stream<dynamic> get onPopState => Stream.empty();

  Future<void> callMethod(String method, List args) async {
    throw UnsupportedError('JS interop is not supported on this platform');
  }

  bool callBoolMethod(String method, List args) {
    throw UnsupportedError('JS interop is not supported on this platform');
  }

  Future<bool> callFutureBoolMethod(String method, List args) {
    throw UnsupportedError('JS interop is not supported on this platform');
  }

  // Corrected return type to match web implementation
  Future<dynamic> callFutureMethod(String method, List args) {
    throw UnsupportedError('JS interop is not supported on this platform');
  }

  String getOSInsideWeb() {
    throw UnsupportedError('JS interop is not supported on this platform');
  }

  /// Kept for compatibility.
  void changeUrl(String newUrl) {
    throw UnsupportedError('JS interop is not supported on this platform');
  }

  void pushState(String newUrl) {
    throw UnsupportedError('JS interop is not supported on this platform');
  }

  void goBack() {
    throw UnsupportedError('JS interop is not supported on this platform');
  }

  String getCurrentUrl() {
    throw UnsupportedError('JS interop is not supported on this platform');
  }
}
