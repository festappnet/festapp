import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart' deferred as font_runtime;

/// Loads the dynamic font registry only for a form that actually needs it.
/// Failed downloads are not retained, so a recovered connection can retry.
class FormFontCatalog {
  const FormFontCatalog._();

  static Future<FormFontCatalog>? _pending;
  static FormFontCatalog? _loaded;

  static Future<FormFontCatalog> load() {
    final loaded = _loaded;
    return loaded != null ? Future.value(loaded) : _pending ??= _load();
  }

  static Future<FormFontCatalog> _load() async {
    try {
      await Future<void>.sync(font_runtime.loadLibrary);
      return _loaded = const FormFontCatalog._();
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

  Future<TextStyle> previewStyle(String family) async {
    final style = getFont(family);
    await font_runtime.GoogleFonts.pendingFonts([style]);
    return style;
  }

  TextTheme getTextTheme(String family, TextTheme base) =>
      font_runtime.GoogleFonts.getTextTheme(family, base);
}
