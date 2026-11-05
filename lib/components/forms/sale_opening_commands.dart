import 'sale_opening_protection.dart';

import 'package:supabase_flutter/supabase_flutter.dart';

class SaleOpeningCommands {
  static Future<Map<String, dynamic>> execute(
    String operation,
    Map<String, dynamic> payload,
  ) async {
    if (operation == 'subscribe') {
      final config = await Supabase.instance.client.functions.invoke(
        'sale-opening-notifications',
        body: {'operation': 'protection'},
      );
      if (config.status != 200 ||
          config.data?['ok'] != true ||
          config.data?['siteKey'] is! String) {
        throw StateError('verification_unavailable');
      }
      final botToken = await verifySaleOpeningVisitor(
        config.data['siteKey'] as String,
        payload['formLink'] as String,
        payload['email'] as String,
      );
      payload = {...payload, 'botToken': botToken};
    }
    final response = await Supabase.instance.client.functions.invoke(
      'sale-opening-notifications',
      body: {'operation': operation, ...payload},
    );
    if (response.status != 200 || response.data?['ok'] != true) {
      throw StateError(
        response.status == 429 ? 'try_later' : 'action_unavailable',
      );
    }
    return Map<String, dynamic>.from(response.data as Map);
  }
}
