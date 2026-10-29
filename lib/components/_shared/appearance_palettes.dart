import 'package:easy_localization/easy_localization.dart';

/// Color identity is independent of saved editing IDs and typography.
class AppearancePalette {
  const AppearancePalette(
    this.id,
    this.labelKey,
    this.primary,
    this.secondary, {
    this.fontFamily,
  });
  final String id;
  final String labelKey;
  final int primary;
  final int secondary;
  // Retains the setup preset manifest; choosing colors does not change the font.
  final String? fontFamily;
  String get label => labelKey.tr();
  String get primaryHex => primary.toRadixString(16).substring(2).toUpperCase();
  String get secondaryHex =>
      secondary.toRadixString(16).substring(2).toUpperCase();
}

class AppearancePalettes {
  static const all = <AppearancePalette>[
    AppearancePalette(
      'clean',
      'OccasionSetup.ui.clean',
      0xff4465A6,
      0xff4465A6,
      fontFamily: 'Roboto',
    ),
    AppearancePalette(
      'gala',
      'OccasionSetup.ui.gala',
      0xff14284B,
      0xffA87F28,
      fontFamily: 'Roboto Slab',
    ),
    AppearancePalette(
      'energy',
      'OccasionSetup.ui.energetic',
      0xffBB350C,
      0xff8B182E,
      fontFamily: 'Russo One',
    ),
    AppearancePalette(
      'nature',
      'OccasionSetup.ui.natural',
      0xff216445,
      0xff146475,
      fontFamily: 'Roboto',
    ),
    AppearancePalette(
      'soft',
      'OccasionSetup.ui.soft',
      0xff885268,
      0xffB89A68,
      fontFamily: 'Roboto Slab',
    ),
    AppearancePalette(
      'contrast',
      'OccasionSetup.ui.contrast',
      0xff111111,
      0xff111111,
      fontFamily: 'Roboto',
    ),
    AppearancePalette(
      'ocean',
      'OccasionSetup.ui.palette_ocean',
      0xff075985,
      0xff0F766E,
      fontFamily: 'Open Sans',
    ),
    AppearancePalette(
      'royal',
      'OccasionSetup.ui.palette_royal',
      0xff312E81,
      0xff7E22CE,
      fontFamily: 'Playfair Display',
    ),
    AppearancePalette(
      'lavender',
      'OccasionSetup.ui.palette_lavender',
      0xff6D28D9,
      0xffA855A0,
      fontFamily: 'Lato',
    ),
    AppearancePalette(
      'citrus',
      'OccasionSetup.ui.palette_citrus',
      0xff3F6212,
      0xffA16207,
      fontFamily: 'Montserrat',
    ),
    AppearancePalette(
      'sunset',
      'OccasionSetup.ui.palette_sunset',
      0xffC2410C,
      0xff9D174D,
      fontFamily: 'Poppins',
    ),
    AppearancePalette(
      'wine',
      'OccasionSetup.ui.palette_wine',
      0xff701A3C,
      0xff9F1239,
      fontFamily: 'Roboto Slab',
    ),
    AppearancePalette(
      'terracotta',
      'OccasionSetup.ui.palette_terracotta',
      0xff9A3412,
      0xff92400E,
      fontFamily: 'Oswald',
    ),
    AppearancePalette(
      'forest',
      'OccasionSetup.ui.palette_forest',
      0xff14532D,
      0xff365314,
      fontFamily: 'Open Sans',
    ),
    AppearancePalette(
      'graphite',
      'OccasionSetup.ui.palette_graphite',
      0xff334155,
      0xff475569,
      fontFamily: 'Inter',
    ),
    AppearancePalette(
      'rose',
      'OccasionSetup.ui.palette_rose',
      0xff9D174D,
      0xffBE185D,
      fontFamily: 'Playfair Display',
    ),
    AppearancePalette(
      'azure',
      'OccasionSetup.ui.palette_azure',
      0xff1D4ED8,
      0xff0369A1,
      fontFamily: 'Montserrat',
    ),
    AppearancePalette(
      'cream',
      'OccasionSetup.ui.palette_cream',
      0xff785A38,
      0xffA16207,
      fontFamily: 'Lato',
    ),
    AppearancePalette(
      'form-ocean',
      'AppearanceColors.names.ocean',
      0xFF0288D1,
      0xFFE1F5FE,
    ),
    AppearancePalette(
      'form-forest',
      'AppearanceColors.names.forest',
      0xFF2E7D32,
      0xFFE8F5E9,
    ),
    AppearancePalette(
      'form-sunset',
      'AppearanceColors.names.sunset',
      0xFFE64A19,
      0xFFFBE9E7,
    ),
    AppearancePalette(
      'form-lavender',
      'AppearanceColors.names.lavender',
      0xFF673AB7,
      0xFFEDE7F6,
    ),
    AppearancePalette(
      'form-night',
      'AppearanceColors.names.night',
      0xFF263238,
      0xFFECEFF1,
    ),
    AppearancePalette(
      'form-berry',
      'AppearanceColors.names.berry',
      0xFF880E4F,
      0xFFFCE4EC,
    ),
    AppearancePalette(
      'form-teal',
      'AppearanceColors.names.teal',
      0xFF00695C,
      0xFFE0F2F1,
    ),
    AppearancePalette(
      'form-gold',
      'AppearanceColors.names.gold',
      0xFFFF8F00,
      0xFFFFF8E1,
    ),
    AppearancePalette(
      'form-cherry',
      'AppearanceColors.names.cherry',
      0xFFC2185B,
      0xFFF8BBD0,
    ),
    AppearancePalette(
      'form-royal',
      'AppearanceColors.names.royal',
      0xFF1565C0,
      0xFFE3F2FD,
    ),
    AppearancePalette(
      'form-slate',
      'AppearanceColors.names.slate',
      0xFF455A64,
      0xFFECEFF1,
    ),
    AppearancePalette(
      'form-cozy',
      'AppearanceColors.names.cozy',
      0xFF5D4037,
      0xFFEFEBE9,
    ),
    AppearancePalette(
      'form-mint',
      'AppearanceColors.names.mint',
      0xFF00796B,
      0xFFE0F2F1,
    ),
    AppearancePalette(
      'form-coral',
      'AppearanceColors.names.coral',
      0xFFFF5722,
      0xFFFBE9E7,
    ),
    AppearancePalette(
      'form-indigo',
      'AppearanceColors.names.indigo',
      0xFF3F51B5,
      0xFFE8EAF6,
    ),
    AppearancePalette(
      'form-lime',
      'AppearanceColors.names.lime',
      0xFF827717,
      0xFFF9FBE7,
    ),
  ];

  static AppearancePalette byId(String id) => all.firstWhere((p) => p.id == id);

  static AppearancePalette? match(int? primary, int? secondary, bool gradient) {
    if (primary == null) return null;
    for (final palette in all) {
      if (palette.primary == primary &&
          (!gradient || palette.secondary == secondary)) {
        return palette;
      }
    }
    return null;
  }
}
