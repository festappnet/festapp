import 'package:file_picker_web/src/preload_policy.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('preloads files up to 2 GB when withData is true', () {
    expect(shouldPreloadBytes(0, withData: true), isTrue);
    expect(shouldPreloadBytes(maxPreloadBytes, withData: true), isTrue);
  });

  test('does not preload files larger than 2 GB', () {
    expect(shouldPreloadBytes(maxPreloadBytes + 1, withData: true), isFalse);
    expect(shouldPreloadBytes(2400 * 1024 * 1024, withData: true), isFalse);
  });

  test('never preloads when withData is false', () {
    expect(shouldPreloadBytes(1, withData: false), isFalse);
  });
}
