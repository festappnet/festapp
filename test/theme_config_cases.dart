import 'package:adaptive_theme/adaptive_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fstapp/theme_config.dart';

void main() {
  testWidgets('enabled buttons have a brand outline without changing geometry',
      (tester) async {
    for (final brightness in Brightness.values) {
      final theme = ThemeConfig.theme(brightness: brightness);
      final style = theme.elevatedButtonTheme.style!;
      expect(style.side!.resolve({})!.color,
          theme.primaryColor.withValues(alpha: .35));
      expect(style.side!.resolve({WidgetState.disabled}), BorderSide.none);
      expect(style.backgroundColor!.resolve({WidgetState.disabled}), isNull);
      final enabledColor = style.backgroundColor!.resolve({})!;
      expect(contrastRatio(enabledColor, theme.primaryColor),
          greaterThanOrEqualTo(4.5));
      Future<Size> buttonSize(
          ThemeData buttonTheme, VoidCallback? onPressed) async {
        await tester.pumpWidget(MaterialApp(
            theme: buttonTheme,
            home: Scaffold(
              body: Center(
                  child: ElevatedButton(
                      onPressed: onPressed, child: const Text('Save changes'))),
            )));
        await tester.pumpAndSettle();
        return tester.getSize(find.byType(ElevatedButton));
      }

      final original =
          theme.copyWith(elevatedButtonTheme: const ElevatedButtonThemeData());
      expect(await buttonSize(theme, () {}), await buttonSize(original, () {}));
      expect(await buttonSize(theme, null), await buttonSize(original, null));
    }
  });

  test('dark mode is available but defaults to light mode', () {
    expect(ThemeConfig.isDarkModeEnabled, isTrue);
    expect(ThemeConfig.defaultThemeMode, AdaptiveThemeMode.light);
  });

  test('both themes use Material 3 and preserve tenant primary and font', () {
    final light = ThemeConfig.theme();
    final dark = ThemeConfig.theme(brightness: Brightness.dark);
    for (final theme in [light, dark]) {
      expect(theme.useMaterial3, isTrue);
      expect(theme.textTheme.bodyMedium!.fontFamily, ThemeConfig.fontFamily);
      expect(theme.primaryColor, theme.colorScheme.primary);
      expect(
          contrastRatio(theme.colorScheme.primary, theme.colorScheme.onPrimary),
          greaterThanOrEqualTo(4.5));
      expect(
          contrastRatio(theme.colorScheme.surface, theme.colorScheme.onSurface),
          greaterThanOrEqualTo(4.5));
      expect(
          contrastRatio(
              theme.scaffoldBackgroundColor, theme.colorScheme.onSurface),
          greaterThanOrEqualTo(4.5));
      expect(
          contrastRatio(theme.appBarTheme.backgroundColor!,
              theme.appBarTheme.foregroundColor!),
          greaterThanOrEqualTo(4.5));
    }
    expect(light.colorScheme.primary, ThemeConfig.lllPrimary);
    expect(dark.colorScheme.primary, ThemeConfig.dddPrimary);
    expect(light.scaffoldBackgroundColor, ThemeConfig.lllBackground);
    expect(dark.scaffoldBackgroundColor, ThemeConfig.dddBackground);
  });

  test('custom form and tenant colors use readable foregrounds in both modes',
      () {
    for (final brightness in Brightness.values) {
      for (final primary in [
        Colors.yellow,
        Colors.blue,
        Colors.white,
        Colors.black
      ]) {
        final scheme = ThemeConfig.colorSchemeForBrand(
          primary: primary,
          secondary: Colors.orange,
          brightness: brightness,
        );
        expect(scheme.primary, primary);
        expect(scheme.secondary, Colors.orange);
        for (final pair in [
          [scheme.primary, scheme.onPrimary],
          [scheme.secondary, scheme.onSecondary],
          [scheme.primaryContainer, scheme.onPrimaryContainer],
          [scheme.surface, scheme.onSurfaceVariant],
        ]) {
          expect(contrastRatio(pair[0], pair[1]), greaterThanOrEqualTo(4.5));
        }
      }
    }
  });

  test(
      'system bars choose platform icon brightness for their actual backgrounds',
      () {
    for (final background in [Colors.white, Colors.black]) {
      final overlay =
          ThemeConfig.systemUiOverlayStyle(statusBarColor: background);
      expect(overlay.statusBarColor, background);
      final dark = background == Colors.black;
      expect(overlay.statusBarIconBrightness,
          dark ? Brightness.light : Brightness.dark);
      expect(overlay.statusBarBrightness,
          dark ? Brightness.dark : Brightness.light);
      expect(overlay.systemNavigationBarColor, ThemeConfig.appBarColor());
      expect(overlay.systemNavigationBarIconBrightness, Brightness.light);
      expect(overlay.systemNavigationBarContrastEnforced, isFalse);
      expect(
          ThemeConfig.theme()
              .appBarTheme
              .systemOverlayStyle!
              .systemNavigationBarColor,
          ThemeConfig.appBarColor());
    }
  });

  test('dark color scheme keeps secondary content readable', () {
    final darkTheme = ThemeConfig.theme(brightness: Brightness.dark);

    expect(darkTheme.colorScheme.brightness, Brightness.dark);
    expect(
      darkTheme.colorScheme.onSurfaceVariant.computeLuminance(),
      greaterThan(0.4),
    );
  });
}

double contrastRatio(Color a, Color b) {
  final first = a.computeLuminance();
  final second = b.computeLuminance();
  return first > second
      ? (first + 0.05) / (second + 0.05)
      : (second + 0.05) / (first + 0.05);
}
