import 'package:festapp_core/json_values.dart';

/// One server-owned read contract; clients never infer payment or admission state.
class CustomerOrderOverview {
  CustomerOrderOverview(Map<String, dynamic> value)
    : data = freezeJsonValue(value) as Map<String, dynamic> {
    if (value['code'] != 200 || value['root'] is! Map) {
      throw StateError('INVALID_CAPABILITY');
    }
  }
  final Map<String, dynamic> data;
  Map get root => data['root'] as Map;
  List get people => data['people'] as List;
  List get offers => data['offers'] as List;
  List get orders => data['orders'] as List;
  bool get hasPendingOffer =>
      offers.any((o) => (o['pendingPlaces'] as num) > 0);
}

class CustomerOrderScope {
  const CustomerOrderScope(this.token, this.orderId);
  final String token;
  final int orderId;
  static CustomerOrderScope? fromFragment(String fragment) {
    if (!fragment.startsWith('order?')) return null;
    final params = Uri.splitQueryString(fragment.substring(6));
    final token = params['token'] ?? '';
    final id = int.tryParse(params['order_id'] ?? '');
    if (!RegExp(r'^[a-f0-9]{64}$').hasMatch(token) || id == null || id <= 0) {
      throw StateError('INVALID_CAPABILITY');
    }
    return CustomerOrderScope(token, id);
  }

  String get fragment =>
      'order?${Uri(queryParameters: {'order_id': '$orderId', 'token': token}).query}';
}
