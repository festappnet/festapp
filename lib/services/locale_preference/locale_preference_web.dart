import 'dart:convert';
import 'dart:js_interop';

import 'package:flutter/foundation.dart';
import 'package:fstapp/app_config.dart';
import 'package:web/web.dart' as web;

import 'locale_preference_store.dart';

LocalePreferenceStore createLocalePreferenceStore() => const _BrowserStore();

class _BrowserStore implements LocalePreferenceStore {
  const _BrowserStore();
  @override
  bool get enabled => true;
  String? _supported(String? value) {
    final language = value?.toLowerCase().split(RegExp('[_-]')).first;
    return AppConfig.availableLanguages().any(
          (item) => item.locale.languageCode == language,
        )
        ? language
        : null;
  }

  @override
  String? read() {
    try {
      final saved = jsonDecode(
        web.window.localStorage.getItem('flutter.locale') ?? 'null',
      );
      final language = saved is String ? _supported(saved) : null;
      if (language != null) return language;
    } catch (_) {
      // A malformed value must not prevent using the previous public choice.
    }
    try {
      return _supported(web.window.localStorage.getItem('locale'));
    } catch (_) {
      return null;
    }
  }

  @override
  VoidCallback listen(VoidCallback onChanged) {
    final storage = ((web.StorageEvent event) {
      if (event.key == 'flutter.locale' ||
          event.key == 'locale' ||
          event.key == null) {
        onChanged();
      }
    }).toJS;
    final resume = ((web.Event event) => onChanged()).toJS;
    web.window.addEventListener('storage', storage);
    web.window.addEventListener('focus', resume);
    web.window.addEventListener('pageshow', resume);
    return () {
      web.window.removeEventListener('storage', storage);
      web.window.removeEventListener('focus', resume);
      web.window.removeEventListener('pageshow', resume);
    };
  }
}
