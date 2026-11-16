import 'package:easy_localization/easy_localization.dart';

import 'dart:convert';

import 'package:flutter/services.dart';
import 'package:flutter/foundation.dart' show SynchronousFuture;

import '../features/ticket_feature.dart';

class TicketDeliveryStrings {
  static final _walletCopies = <String, Map<String, String>>{};

  /// Email language can differ from the editor's interface language. Retain only
  /// the small Wallet copy, without repeatedly decoding whole locale bundles.
  static Future<Map<String, String>> walletCopy(String language) {
    final lang = const {'cs', 'sk', 'en', 'de', 'pl', 'uk'}.contains(language)
        ? language
        : 'en';
    final cached = _walletCopies[lang];
    if (cached != null) return SynchronousFuture(cached);
    return rootBundle.loadString('assets/translations/$lang.json').then((raw) {
      final source = jsonDecode(raw) as Map;
      final copy = source['TicketDelivery'] as Map;
      final result = Map<String, String>.unmodifiable({
        for (final key in const [
          'Title',
          'Help',
          'Ticket',
          'Fallback',
          'Button',
        ])
          key: copy['walletEmail$key'] as String,
      });
      _walletCopies[lang] = result;
      return result;
    });
  }

  static String text(String key) => 'TicketDelivery.$key'.tr();
  static String label(TicketDeliveryMode mode) => text(mode.value);
  static String description(TicketDeliveryMode mode) =>
      text('${mode.value}Help');
}
