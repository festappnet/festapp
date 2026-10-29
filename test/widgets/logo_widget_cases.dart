import 'package:flutter_test/flutter_test.dart';
import 'package:fstapp/app_config.dart';
import 'package:fstapp/widgets/logo_widget.dart';

void main() {
  test('compact ticketing logo keeps only the symbol in both themes', () {
    if (Uri.parse(AppConfig.webLink).host != 'vstupenky.online') return;
    for (final dark in [false, true]) {
      expect(
        resolveLogoAsset(
          isDarkMode: dark,
          forceDark: null,
          programVariant: false,
          compact: true,
        ),
        dark
            ? 'assets/icons/vstupenky-symbol.dark.svg'
            : 'assets/icons/vstupenky-symbol.svg',
      );
    }
    expect(
      resolveLogoAsset(
        isDarkMode: false,
        forceDark: true,
        programVariant: true,
        compact: true,
      ),
      'assets/icons/vstupenky-symbol.dark.svg',
    );
  });

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
