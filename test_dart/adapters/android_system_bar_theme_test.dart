import 'dart:io';

import 'package:test/test.dart';

void main() {
  test('Android themes keep system navigation on the CSM dark chrome', () {
    for (final path in [
      'android/app/src/main/res/values/styles.xml',
      'android/app/src/main/res/values-night/styles.xml',
    ]) {
      final styles = File(path).readAsStringSync();

      expect(
        RegExp(r'<item name="android:navigationBarColor">#FF0D1626</item>')
            .allMatches(styles)
            .length,
        2,
        reason: '$path must cover both LaunchTheme and NormalTheme',
      );
      expect(
        RegExp(r'<item name="android:windowLightNavigationBar">false</item>')
            .allMatches(styles)
            .length,
        2,
        reason: '$path must request light navigation icons on the dark bar',
      );
      expect(
        RegExp(r'<item name="android:enforceNavigationBarContrast">false</item>')
            .allMatches(styles)
            .length,
        2,
        reason: '$path must prevent Android from adding a light contrast scrim',
      );
    }
  });
}
