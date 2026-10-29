import 'dart:convert';
import 'dart:js_interop';

import 'package:flutter/foundation.dart';
import 'package:web/web.dart' as web;

import 'theme_preference_store.dart';

ThemePreferenceStore createThemePreferenceStore() => const _BrowserStore();

class _BrowserStore implements ThemePreferenceStore {
  const _BrowserStore();
  static const key = 'theme';
  @override
  bool get enabled => true;
  @override
  String? read() {
    try {
      return web.window.localStorage.getItem(key);
    } catch (_) {
      return null;
    }
  }

  @override
  String? readLegacy() {
    for (final key in [
      'adaptive_theme_preferences',
      'flutter.adaptive_theme_preferences',
    ]) {
      try {
        dynamic value = jsonDecode(
          web.window.localStorage.getItem(key) ?? 'null',
        );
        if (value is String) value = jsonDecode(value);
        if (value is Map) {
          final mode = switch (value['theme_mode']) {
            0 => 'light',
            1 => 'dark',
            2 => 'auto',
            _ => null,
          };
          if (mode != null) return mode;
        }
      } catch (_) {
        /* Malformed or unavailable storage must not block startup. */
      }
    }
    return null;
  }

  @override
  void write(String mode) {
    try {
      if (read() != mode) web.window.localStorage.setItem(key, mode);
    } catch (_) {
      /* The current tab still supports in-memory theme changes. */
    }
  }

  @override
  VoidCallback listen(VoidCallback onChanged) {
    final storage = ((web.StorageEvent event) {
      if (event.key == key || event.key == null) onChanged();
    }).toJS;
    final resume = ((web.Event event) => onChanged()).toJS;
    web.window.addEventListener('storage', storage);
    web.window.addEventListener('pageshow', resume);
    web.window.addEventListener('focus', resume);
    return () {
      web.window.removeEventListener('storage', storage);
      web.window.removeEventListener('pageshow', resume);
      web.window.removeEventListener('focus', resume);
    };
  }
}
