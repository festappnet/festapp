import 'package:flutter_test/flutter_test.dart';
import 'package:fstapp/app_config.dart';
import 'package:fstapp/widgets/logo_widget.dart';

void main() {
  test('compact ticketing logo keeps only the symbol in both themes', () {
    for (final brand in {
      'https://vstupenky.online': 'assets/icons/vstupenky-symbol',
      'https://tickets.festapp.net':
          'assets/brand/festapp-tickets/festapp-tickets-symbol',
    }.entries) {
      final darkAsset = brand.key.contains('vstupenky.online')
          ? '${brand.value}.dark.svg'
          : '${brand.value}-dark.svg';
      for (final dark in [false, true]) {
        expect(
          resolveLogoAsset(
            isDarkMode: dark,
            forceDark: null,
            programVariant: false,
            compact: true,
            webLink: brand.key,
          ),
          dark ? darkAsset : '${brand.value}.svg',
        );
      }
      expect(
        resolveLogoAsset(
          isDarkMode: false,
          forceDark: true,
          programVariant: true,
          compact: true,
          webLink: brand.key,
        ),
        darkAsset,
      );
    }
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
