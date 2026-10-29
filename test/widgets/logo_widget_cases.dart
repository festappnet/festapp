import 'package:flutter_test/flutter_test.dart';
import 'package:fstapp/app_config.dart';
import 'package:fstapp/widgets/logo_widget.dart';

void main() {
  test('explicit dark logo wins over the program variant', () {
    expect(
      resolveLogoAsset(
        isDarkMode: false,
        forceDark: true,
        programVariant: true,
      ),
      AppConfig.darkLogoAsset,
    );
  });

  test('program variant remains available on a light header', () {
    expect(
      resolveLogoAsset(
        isDarkMode: false,
        forceDark: null,
        programVariant: true,
      ),
      AppConfig.programLogoAsset,
    );
  });
}
