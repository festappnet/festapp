import 'package:festapp_core/payments.dart';
import 'package:festapp_core/sync.dart';
import 'package:fstapp/data_services/client_sync/client_command_identity.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class PaymentNotConfiguredException implements Exception {
  const PaymentNotConfiguredException();
}

abstract interface class PaymentConnectionApi {
  Future<Map<String, dynamic>?> status(int unitId);
  Future<Uri> start(int unitId, {bool replace = false});
  Future<void> pause(int unitId, bool paused);
  Future<Map<String, dynamic>> disconnectImpact(int unitId);
  Future<Map<String, dynamic>> disconnect(int unitId, String connectionId);
  Future<Map<String, dynamic>> complete(Map<String, String> callback);
}

class SupabasePaymentConnectionApi implements PaymentConnectionApi {
  const SupabasePaymentConnectionApi({required this.connector, this.client});
  final PaymentConnector connector;
  final SupabaseClient? client;
  Future<Map<String, dynamic>?> formRecipient(
    int unitId,
    int occasionId,
  ) async {
    final value = await _invoke('payment-connect', {
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
        body: {
          ...body,
          if (name == 'payment-connect') 'provider': connector.id,
        },
      );
    } on FunctionException catch (error) {
      if (error.status == 503 &&
          error.details is Map &&
          error.details['error'] == '${connector.id}_not_configured') {
        throw const PaymentNotConfiguredException();
      }
      rethrow;
    }
    if (response.status != 200 && !(acceptPending && response.status == 202)) {
      throw StateError('payment_connection_unavailable');
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
    final namespace = '$principal:${connector.id}.connection.command';
    final command = await ClientCommandIdentity.claimIntent(
      namespace,
      payload,
      principalBinding: principal,
    );
    if (principalNow() != principal) {
      throw StateError('payment_command_identity_changed');
    }
    final raw = await _invoke('payment-connect', {
      ...payload,
      'commandId': command,
    }, acceptPending: disconnect);
    final response = ClientCommandResponse.from(raw);
    if (principalNow() != principal) {
      throw StateError('payment_command_identity_changed');
    }
    if (response.code != 200) {
      throw StateError('payment_connection_command_rejected');
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
        await _invoke('payment-connect', {
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
    final value = await _invoke('payment-connect', {
      'unitId': unitId,
      'action': 'status',
    });
    return value is Map ? value.cast<String, dynamic>() : null;
  }

  @override
  Future<Uri> start(int unitId, {bool replace = false}) async {
    final data = await _invoke('payment-connect', {
      'unitId': unitId,
      'action': replace ? 'replace' : 'start',
    });
    return connector.authorizationUri(
      data is Map ? data['url']?.toString() ?? '' : '',
    );
  }

  @override
  Future<void> pause(int unitId, bool paused) async {
    await _command({'unitId': unitId, 'action': paused ? 'pause' : 'resume'});
  }

  @override
  Future<Map<String, dynamic>> complete(Map<String, String> callback) async {
    final value = await _invoke(
      connector.callbackEndpoint ??
          (throw StateError('payment_callback_unsupported')),
      callback,
    );
    if (value is! Map) throw StateError('payment_connection_unavailable');
    return value.cast<String, dynamic>();
  }
}
