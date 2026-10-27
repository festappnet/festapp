import 'package:festapp_core/sync.dart';
import 'package:fstapp/data_services/client_sync/client_command_identity.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class StripeNotConfiguredException implements Exception {
  const StripeNotConfiguredException();
}

abstract interface class StripeConnectionApi {
  Future<Map<String, dynamic>?> status(int unitId);
  Future<Uri> start(int unitId, {bool replace = false});
  Future<void> pause(int unitId, bool paused);
  Future<Map<String, dynamic>> disconnectImpact(int unitId);
  Future<Map<String, dynamic>> disconnect(int unitId, String connectionId);
  Future<Map<String, dynamic>> complete(Map<String, String> callback);
}

class SupabaseStripeConnectionApi implements StripeConnectionApi {
  const SupabaseStripeConnectionApi({this.client});
  final SupabaseClient? client;
  Future<Map<String, dynamic>?> formRecipient(
    int unitId,
    int occasionId,
  ) async {
    final value = await _invoke('stripe-connect', {
      'unitId': unitId,
      'occasionId': occasionId,
      'action': 'form-options',
    });
    return value is Map ? value.cast<String, dynamic>() : null;
  }

  Future<dynamic> _invoke(
    String name,
    Map<String, dynamic> body, {
    bool acceptPending = false,
  }) async {
    late final FunctionResponse response;
    try {
      response = await (client ?? Supabase.instance.client).functions.invoke(
        name,
        body: body,
      );
    } on FunctionException catch (error) {
      if (error.status == 503 &&
          error.details is Map &&
          error.details['error'] == 'stripe_not_configured') {
        throw const StripeNotConfiguredException();
      }
      rethrow;
    }
    if (response.status != 200 && !(acceptPending && response.status == 202)) {
      throw StateError('stripe_connection_unavailable');
    }
    return response.data;
  }

  Future<Map<String, dynamic>> _command(
    Map<String, dynamic> payload, {
    bool disconnect = false,
  }) async {
    final active = client ?? Supabase.instance.client;
    String principalNow() =>
        '${active.rest.url}:${active.auth.currentUser?.id}';
    final principal = principalNow();
    final namespace = '$principal:stripe.connection.command';
    final command = await ClientCommandIdentity.claimIntent(
      namespace,
      payload,
      principalBinding: principal,
    );
    if (principalNow() != principal) {
      throw StateError('stripe_command_identity_changed');
    }
    final raw = await _invoke('stripe-connect', {
      ...payload,
      'commandId': command,
    }, acceptPending: disconnect);
    final response = ClientCommandResponse.from(raw);
    if (principalNow() != principal) {
      throw StateError('stripe_command_identity_changed');
    }
    if (response.code != 200) {
      throw StateError('stripe_connection_command_rejected');
    }
    final result = Map<String, dynamic>.from(
      disconnect ? response.data['result'] as Map : response.data,
    );
    if (!disconnect || result['disconnected'] == true) {
      await ClientCommandIdentity.completeIntent(
        namespace,
        payload,
        commandId: command,
        principalBinding: principal,
      );
    }
    return result;
  }

  @override
  Future<Map<String, dynamic>> disconnectImpact(int unitId) async =>
      Map<String, dynamic>.from(
        await _invoke('stripe-connect', {
          'unitId': unitId,
          'action': 'disconnect-impact',
        }),
      );
  @override
  Future<Map<String, dynamic>> disconnect(int unitId, String connectionId) =>
      _command({
        'unitId': unitId,
        'action': 'disconnect',
        'connectionId': connectionId,
      }, disconnect: true);

  @override
  Future<Map<String, dynamic>?> status(int unitId) async {
    final value = await _invoke('stripe-connect', {
      'unitId': unitId,
      'action': 'status',
    });
    return value is Map ? value.cast<String, dynamic>() : null;
  }

  @override
  Future<Uri> start(int unitId, {bool replace = false}) async {
    final data = await _invoke('stripe-connect', {
      'unitId': unitId,
      'action': replace ? 'replace' : 'start',
    });
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
    await _command({'unitId': unitId, 'action': paused ? 'pause' : 'resume'});
  }

  @override
  Future<Map<String, dynamic>> complete(Map<String, String> callback) async {
    final value = await _invoke('stripe-connect-callback', callback);
    if (value is! Map) throw StateError('stripe_connection_unavailable');
    return value.cast<String, dynamic>();
  }
}
