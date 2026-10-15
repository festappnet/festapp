/// One server-owned read contract; clients never infer payment or admission state.
class CustomerOrderOverview {
  CustomerOrderOverview(Map<String, dynamic> value) : data = value {
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
  static CustomerOrderScope? fromUri(Uri uri) {
    if (uri.path != '/order' ||
        uri.hasFragment ||
        uri.queryParameters['waitlist'] == '1')
      return null;
    final params = uri.queryParameters;
    final token = params['token'] ?? '';
    final id = int.tryParse(params['order_id'] ?? '');
    if (!RegExp(r'^[a-f0-9]{64}$').hasMatch(token) ||
        id == null ||
        id <= 0 ||
        uri.queryParametersAll['token']?.length != 1 ||
        uri.queryParametersAll['order_id']?.length != 1) {
      throw StateError('INVALID_CAPABILITY');
    }
    return CustomerOrderScope(token, id);
  }

  Uri get uri => Uri(
    path: '/order',
    queryParameters: {'order_id': '$orderId', 'token': token},
  );
}
