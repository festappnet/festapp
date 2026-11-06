import 'package:festapp_core/payments.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

abstract interface class PaymentGateway {
  Future<Map<String, dynamic>> read(String token, {bool returnOnly = false});
  Future<Map<String, dynamic>> prepare(String token);
  Future<Map<String, dynamic>> readHandoff(String token);
  Future<Map<String, dynamic>> prepareHandoff(String token);
}

class SupabasePaymentGateway implements PaymentGateway {
  const SupabasePaymentGateway(this.connector);
  final PaymentConnector connector;
  Future<Map<String, dynamic>> _call(
    String name,
    Map<String, dynamic> body,
  ) async {
    final response = await Supabase.instance.client.functions.invoke(
      name,
      body: {...body, 'provider': connector.id},
    );
    if (response.status != 200 || response.data is! Map)
      throw StateError('payment_unavailable');
    return (response.data as Map).cast<String, dynamic>();
  }

  Map<String, dynamic> _payment(Map<String, dynamic> result) {
    if (result['payment'] is! Map ||
        result['payment']['method'] != connector.id)
      throw StateError('payment_provider_mismatch');
    return (result['payment'] as Map).cast<String, dynamic>();
  }

  @override
  Future<Map<String, dynamic>> read(
    String token, {
    bool returnOnly = false,
  }) async => _payment(
    await _call(returnOnly ? 'payment-return' : 'payment-checkout', {
      'token': token,
      if (!returnOnly) 'action': 'status',
    }),
  );
  @override
  Future<Map<String, dynamic>> prepare(String token) =>
      _call('payment-checkout', {'token': token});
  @override
  Future<Map<String, dynamic>> readHandoff(String token) async => _payment(
    await _call('payment-checkout', {
      'token': token,
      'action': 'status_handoff',
    }),
  );
  @override
  Future<Map<String, dynamic>> prepareHandoff(String token) =>
      _call('payment-checkout', {'token': token, 'action': 'handoff'});
}
