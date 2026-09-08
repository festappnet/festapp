import 'package:flutter_test/flutter_test.dart';
import 'package:maplibre_android/src/map_state.dart';

void main() {
  test('style-loaded callback crosses JNI asynchronously', () {
    final callback = MapLibreStyleLoadedCallback((_) {});

    expect(callback.onStyleLoaded$async, isTrue);
  });
}
