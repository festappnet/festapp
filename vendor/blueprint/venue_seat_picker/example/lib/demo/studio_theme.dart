import 'package:material_ui/material_ui.dart';

ThemeData studioTheme() {
  const ink = Color(0xff182230), muted = Color(0xff667085);
  const border = Color(0xffdfe4eb), accent = Color(0xff2563eb);
  final shape = RoundedRectangleBorder(borderRadius: BorderRadius.circular(6));
  final base = ThemeData(useMaterial3: true);
  final colors = ColorScheme.fromSeed(seedColor: accent).copyWith(
    primary: accent,
    onPrimary: Colors.white,
    primaryContainer: const Color(0xffeaf1ff),
    onPrimaryContainer: const Color(0xff1d4ed8),
    secondaryContainer: const Color(0xffedf2fa),
    surface: Colors.white,
    surfaceContainerLowest: Colors.white,
    surfaceContainerLow: const Color(0xfff8fafc),
    surfaceContainer: const Color(0xfff3f5f8),
    surfaceContainerHigh: const Color(0xffedf0f5),
    surfaceContainerHighest: const Color(0xffe8ecf2),
    onSurface: ink,
    onSurfaceVariant: muted,
    outline: const Color(0xff98a2b3),
    outlineVariant: border,
  );
  final buttons = ButtonStyle(
    shape: WidgetStatePropertyAll(shape),
    minimumSize: const WidgetStatePropertyAll(Size(36, 36)),
    padding: const WidgetStatePropertyAll(EdgeInsets.symmetric(horizontal: 14)),
    textStyle: const WidgetStatePropertyAll(
      TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
    ),
  );
  final inputBorder = OutlineInputBorder(
    borderRadius: BorderRadius.circular(6),
    borderSide: const BorderSide(color: border),
  );
  return base.copyWith(
    colorScheme: colors,
    scaffoldBackgroundColor: colors.surfaceContainer,
    textTheme: base.textTheme
        .apply(bodyColor: ink, displayColor: ink)
        .copyWith(
          bodyMedium: const TextStyle(fontSize: 13, height: 1.45, color: ink),
          bodyLarge: const TextStyle(fontSize: 14, height: 1.45, color: ink),
          labelLarge: const TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w600,
            color: ink,
          ),
          titleMedium: const TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.w600,
            color: ink,
          ),
        ),
    appBarTheme: const AppBarTheme(
      backgroundColor: Colors.white,
      foregroundColor: ink,
      surfaceTintColor: Colors.transparent,
      elevation: 0,
      scrolledUnderElevation: 0,
      toolbarHeight: 72,
      shape: Border(bottom: BorderSide(color: border)),
    ),
    dividerTheme: const DividerThemeData(color: border, thickness: 1, space: 1),
    iconTheme: const IconThemeData(size: 18, color: muted),
    iconButtonTheme: IconButtonThemeData(
      style: buttons.copyWith(
        padding: const WidgetStatePropertyAll(EdgeInsets.all(8)),
        iconSize: const WidgetStatePropertyAll(18),
      ),
    ),
    textButtonTheme: TextButtonThemeData(style: buttons),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: buttons.copyWith(
        side: const WidgetStatePropertyAll(BorderSide(color: border)),
      ),
    ),
    filledButtonTheme: FilledButtonThemeData(style: buttons),
    inputDecorationTheme: InputDecorationTheme(
      isDense: true,
      filled: true,
      fillColor: const Color(0xfffbfcfe),
      contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 11),
      labelStyle: const TextStyle(fontSize: 12, color: muted),
      border: inputBorder,
      enabledBorder: inputBorder,
      focusedBorder: inputBorder.copyWith(
        borderSide: const BorderSide(color: accent, width: 1.5),
      ),
    ),
    tooltipTheme: TooltipThemeData(
      waitDuration: const Duration(milliseconds: 450),
      decoration: BoxDecoration(
        color: ink,
        borderRadius: BorderRadius.circular(5),
      ),
      textStyle: const TextStyle(color: Colors.white, fontSize: 12),
    ),
    popupMenuTheme: PopupMenuThemeData(
      color: Colors.white,
      surfaceTintColor: Colors.transparent,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(8),
        side: const BorderSide(color: border),
      ),
    ),
  );
}
