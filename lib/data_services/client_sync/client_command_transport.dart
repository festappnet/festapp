import 'dart:async';
import 'dart:convert';
import 'package:fstapp/data_services/client_sync/client_command_response.dart';
import 'package:fstapp/data_services/client_sync/client_command_identity.dart';

import 'package:http/http.dart' as http;
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:uuid/uuid.dart';

typedef ClientCommandRpc = Future<Object?> Function(
  String functionName,
  Map<String, dynamic> parameters,
);

/// Internal transport for typed command adapters.
///
/// The command UUID is allocated once per invocation and remains stable across
/// transport-level retries. Domain ports remain statically bound to their RPC.
class ClientCommandTransport {
  ClientCommandTransport(this._rpc, {this.maxAttempts = 2});

  factory ClientCommandTransport.supabase(SupabaseClient client) =>
      ClientCommandTransport(
        (functionName, parameters) =>
            client.rpc(functionName, params: parameters),
      );

  final ClientCommandRpc _rpc;
  final int maxAttempts;
  final Map<String, _PendingCommand> _pending = {};

  /// Retains immutable bytes and identity through ambiguous transport failures.
  /// Namespace includes actor, occasion and the editor aggregate/intent.
  Future<Object?> invokeIntent(
      String namespace, String functionName, Map<String, dynamic> parameters) {
    final snapshot = jsonDecode(jsonEncode(parameters)) as Map<String, dynamic>;
    final key = '$namespace:${ClientCommandIdentity.fingerprint(snapshot)}';
    final pending = _pending.putIfAbsent(key,
        () => _PendingCommand(ClientCommandIdentity.newCommandId(), snapshot));
    if (pending.inFlight != null) return pending.inFlight!;
    final flight =
        invoke(functionName, pending.parameters, commandId: pending.id);
    final validated = flight.then((response) {
      // A malformed/ambiguous response retains identity for exact replay.
      final parsed = ClientCommandResponse.from(response);
      if (parsed.mutation['commandId'] != pending.id) {
        throw const FormatException('Command response identity mismatch');
      }
      _pending.remove(key);
      return response;
    }).whenComplete(() {
      pending.inFlight = null;
    });
    pending.inFlight = validated;
    return validated;
  }

  Future<Object?> invoke(String functionName, Map<String, dynamic> parameters,
      {String? commandId}) async {
    commandId ??= const Uuid().v4();
    final boundParameters = <String, dynamic>{
      ...parameters,
      'p_command_id': commandId,
    };
    for (var attempt = 1; attempt <= maxAttempts; attempt++) {
      try {
        return await _rpc(functionName, boundParameters);
      } on TimeoutException {
        if (attempt == maxAttempts) rethrow;
      } on http.ClientException {
        if (attempt == maxAttempts) rethrow;
      }
    }
    throw StateError('Command retry loop completed without a result');
  }
}

class _PendingCommand {
  _PendingCommand(this.id, this.parameters);
  final String id;
  final Map<String, dynamic> parameters;
  Future<Object?>? inFlight;
}
