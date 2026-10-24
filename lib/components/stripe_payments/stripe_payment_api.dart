import 'package:supabase_flutter/supabase_flutter.dart';

abstract interface class StripePaymentGateway {
  Future<Map<String, dynamic>> read(String token, {bool returnOnly = false});
  Future<Map<String, dynamic>> prepare(String token);
  Future<Map<String, dynamic>> readHandoff(String token);
  Future<Map<String, dynamic>> prepareHandoff(String token);
}

class SupabaseStripePaymentGateway implements StripePaymentGateway {
  const SupabaseStripePaymentGateway();
  Future<Map<String, dynamic>> _call(
      String name, Map<String, dynamic> body) async {
    final response =
        await Supabase.instance.client.functions.invoke(name, body: body);
    if (response.status != 200 || response.data is! Map) {
      throw StateError('stripe_payment_unavailable');
    }
    return (response.data as Map).cast<String, dynamic>();
  }

  @override
  Future<Map<String, dynamic>> read(String token,
      {bool returnOnly = false}) async {
    final result =
        await _call(returnOnly ? 'stripe-return' : 'stripe-checkout', {
      'token': token,
      if (!returnOnly) 'action': 'status',
    });
    return _payment(result);
  }

  Map<String, dynamic> _payment(Map<String, dynamic> result) {
    if (result['payment'] is! Map || result['payment']['method'] != 'stripe') {
      throw StateError('stripe_payment_unavailable');
    }
    return (result['payment'] as Map).cast<String, dynamic>();
  }

  @override
  Future<Map<String, dynamic>> prepare(String token) =>
      _call('stripe-checkout', {'token': token});

  @override
  Future<Map<String, dynamic>> readHandoff(String token) async =>
      _payment(await _call(
          'stripe-checkout', {'token': token, 'action': 'status_handoff'}));

  @override
  Future<Map<String, dynamic>> prepareHandoff(String token) =>
      _call('stripe-checkout', {'token': token, 'action': 'handoff'});
}
