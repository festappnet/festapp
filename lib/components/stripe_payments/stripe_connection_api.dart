import 'package:supabase_flutter/supabase_flutter.dart';

abstract interface class StripeConnectionApi {
  Future<Map<String, dynamic>?> status(int unitId);
  Future<Uri> start(int unitId, {bool replace = false});
  Future<void> pause(int unitId, bool paused);
  Future<Map<String, dynamic>> disconnectImpact(int unitId);
  Future<Map<String, dynamic>> disconnect(int unitId, String connectionId);
  Future<Map<String, dynamic>> complete(Map<String, String> callback);
}

class SupabaseStripeConnectionApi implements StripeConnectionApi {
  const SupabaseStripeConnectionApi();
  Future<Map<String, dynamic>?> formRecipient(
      int unitId, int occasionId) async {
    final value = await _invoke('stripe-connect',
        {'unitId': unitId, 'occasionId': occasionId, 'action': 'form-options'});
    return value is Map ? value.cast<String, dynamic>() : null;
  }

  Future<dynamic> _invoke(String name, Map<String, dynamic> body,
      {bool acceptPending = false}) async {
    final response =
        await Supabase.instance.client.functions.invoke(name, body: body);
    if (response.status != 200 && !(acceptPending && response.status == 202)) {
      throw StateError('stripe_connection_unavailable');
    }
    return response.data;
  }

  @override
  Future<Map<String, dynamic>> disconnectImpact(int unitId) async =>
      Map<String, dynamic>.from(await _invoke(
          'stripe-connect', {'unitId': unitId, 'action': 'disconnect-impact'}));
  @override
  Future<Map<String, dynamic>> disconnect(
          int unitId, String connectionId) async =>
      Map<String, dynamic>.from(await _invoke(
          'stripe-connect',
          {
            'unitId': unitId,
            'action': 'disconnect',
            'connectionId': connectionId
          },
          acceptPending: true));

  @override
  Future<Map<String, dynamic>?> status(int unitId) async {
    final value =
        await _invoke('stripe-connect', {'unitId': unitId, 'action': 'status'});
    return value is Map ? value.cast<String, dynamic>() : null;
  }

  @override
  Future<Uri> start(int unitId, {bool replace = false}) async {
    final data = await _invoke('stripe-connect',
        {'unitId': unitId, 'action': replace ? 'replace' : 'start'});
    final uri = Uri.tryParse(data is Map ? data['url']?.toString() ?? '' : '');
    if (uri == null ||
        uri.scheme != 'https' ||
        uri.host != 'connect.stripe.com' ||
        uri.userInfo.isNotEmpty ||
        uri.path != '/oauth/authorize') {
      throw StateError('stripe_authorization_url_invalid');
    }
    return uri;
  }

  @override
  Future<void> pause(int unitId, bool paused) async {
    await _invoke('stripe-connect',
        {'unitId': unitId, 'action': paused ? 'pause' : 'resume'});
  }

  @override
  Future<Map<String, dynamic>> complete(Map<String, String> callback) async {
    final value = await _invoke('stripe-connect-callback', callback);
    if (value is! Map) throw StateError('stripe_connection_unavailable');
    return value.cast<String, dynamic>();
  }
}
