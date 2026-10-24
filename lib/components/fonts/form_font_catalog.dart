import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart' deferred as font_runtime;

/// Loads the dynamic font registry only for a form that actually needs it.
/// Failed downloads are not retained, so a recovered connection can retry.
class FormFontCatalog {
  const FormFontCatalog._();

  static Future<FormFontCatalog>? _pending;

  static Future<FormFontCatalog> load() => _pending ??= _load();

  static Future<FormFontCatalog> _load() async {
    try {
      await Future<void>.sync(font_runtime.loadLibrary);
      return const FormFontCatalog._();
    } catch (_) {
      _pending = null;
      rethrow;
    }
  }

  List<String> get families =>
      font_runtime.GoogleFonts.asMap().keys.toList(growable: false);

  Future<void> ensureFamily(String family) async {
    font_runtime.GoogleFonts.getTextTheme(family);
    await font_runtime.GoogleFonts.pendingFonts();
  }

  TextStyle getFont(String family) => font_runtime.GoogleFonts.getFont(family);

  TextTheme getTextTheme(String family, TextTheme base) =>
      font_runtime.GoogleFonts.getTextTheme(family, base);
}
