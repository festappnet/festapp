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
  List<CustomerOrderChangeAction> get allowedActions =>
      (data['allowedActions'] as List? ?? const [])
          .whereType<Map>()
          .map((a) => CustomerOrderChangeAction(Map<String, dynamic>.from(a)))
          .toList(growable: false);
  List<Map<String, dynamic>> get changeRequests =>
      (data['changeRequests'] as List? ?? const [])
          .whereType<Map>()
          .map((r) => Map<String, dynamic>.from(r))
          .toList(growable: false);
  bool get hasPendingOffer =>
      offers.any((o) => (o['pendingPlaces'] as num) > 0);
}

class CustomerOrderScope {
  const CustomerOrderScope(this.token, this.orderId, {this.changeToken});
  final String? changeToken;
  final String token;
  final int orderId;
  static CustomerOrderScope? fromUri(Uri uri) {
    if (uri.path != '/order' ||
        (uri.hasFragment &&
            !RegExp(r'^change=[a-f0-9]{64}$').hasMatch(uri.fragment)) ||
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
    return CustomerOrderScope(
      token,
      id,
      changeToken: uri.hasFragment
          ? Uri.splitQueryString(uri.fragment)['change']
          : null,
    );
  }

  Uri get uri => Uri(
    path: '/order',
    queryParameters: {'order_id': '$orderId', 'token': token},
  );
}

/// Server policy metadata is presentation, never a client write entitlement.
class CustomerOrderChangeAction {
  CustomerOrderChangeAction(this.data) {
    if (!const ['edit', 'cancel', 'move'].contains(data['operation']) ||
        data['enabled'] is! bool)
      throw const FormatException('Invalid customer action');
  }
  final Map<String, dynamic> data;
  String get operation => data['operation'] as String;
  bool get enabled => data['enabled'] == true;
}
