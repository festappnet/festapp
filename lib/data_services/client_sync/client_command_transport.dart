import 'package:festapp_core/sync.dart';
import 'dart:async';
import 'dart:convert';
import 'client_command_identity.dart';

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
  ClientCommandTransport(this._rpc,
      {this.maxAttempts = 2, String? principalBinding,
      String? Function()? principalProvider})
      : _principalBinding = principalBinding,
        _principalProvider = principalProvider;

  factory ClientCommandTransport.supabase(SupabaseClient client,
          {bool durable = false}) =>
      ClientCommandTransport(
        (functionName, parameters) =>
            client.rpc(functionName, params: parameters),
        principalProvider: durable
            ? () => '${client.rest.url}:${client.auth.currentUser?.id ?? 'anonymous'}'
            : null,
      );

  final ClientCommandRpc _rpc;
  final int maxAttempts;
  final String? _principalBinding;
  final String? Function()? _principalProvider;
  String? get principalBinding => _principalProvider?.call() ?? _principalBinding;

  final Map<String, _PendingCommand> _pending = {};

  /// Retains immutable bytes and identity through ambiguous transport failures.
  /// Namespace includes actor, occasion and the editor aggregate/intent.
  Future<Object?> invokeIntent(
      String namespace, String functionName, Map<String, dynamic> parameters) {
    if (principalBinding != null) {
      return invoke(functionName, parameters);
    }
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

  Future<Object?> invoke(
    String functionName,
    Map<String, dynamic> parameters, {
    String? commandId,
  }) async {
    final frozen =
        (jsonDecode(jsonEncode(parameters)) as Map).cast<String, dynamic>();
    final binding = principalBinding;
    if (commandId != null && frozen['p_command_id'] != null &&
        commandId != frozen['p_command_id']) {
      throw ArgumentError('Conflicting command IDs');
    }
    final ownsIntent = binding != null && frozen['p_command_id'] == null && commandId == null;
    final payload = {
      'principal': binding,
      'operation': functionName,
      'parameters': frozen
    };
    final resolvedCommandId = commandId ?? frozen['p_command_id'] ??
        (ownsIntent
            ? await ClientCommandIdentity.claimIntent(functionName, payload,
                principalBinding: binding,
                scopeBinding: jsonEncode(_resourceScope(frozen)),
                requestJson: jsonEncode(frozen))
            : const Uuid().v4());
    if (resolvedCommandId is! String ||
        !RegExp(r'^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$')
            .hasMatch(resolvedCommandId)) {
      throw ArgumentError('Invalid command ID');
    }
    final boundParameters = <String, dynamic>{
      ...frozen,
      'p_command_id': resolvedCommandId,
    };
    for (var attempt = 1; attempt <= maxAttempts; attempt++) {
      try {
        final result = await _rpc(functionName, boundParameters);
        if (binding != null && binding != principalBinding) {
          throw StateError('COMMAND_PRINCIPAL_CHANGED');
        }
        if (result is Map && result['mutation'] is Map &&
            result['mutation']['commandId'] != resolvedCommandId) {
          throw const FormatException('Command response identity mismatch');
        }
        if (ownsIntent &&
            result is Map &&
            result['mutation'] is Map &&
            result['mutation']['commandId'] == resolvedCommandId &&
            (result['code'] == 200 ||
                result['status'] == 'rejected' ||
                result['status'] == 'conflict')) {
          await ClientCommandIdentity.completeIntent(functionName, payload,
              commandId: resolvedCommandId, principalBinding: binding);
        }
        return result;
      } on TimeoutException {
        if (attempt == maxAttempts) rethrow;
      } on http.ClientException {
        if (attempt == maxAttempts) rethrow;
      }
    }
    throw StateError('Command retry loop completed without a result');
  }

  /// Lookup and resume are explicit so a pending operation never silently saves
  /// a newly edited document under the previous command's identity.
  Future<ClientCommandIntent?> pendingIntent(
      String operation, Map<String, dynamic> parameters) async {
    final binding = principalBinding;
    if (binding == null) {
      throw StateError('Durable principal required');
    }
    return ClientCommandIdentity.pendingIntent(operation,
        principalBinding: binding,
        scopeBinding: jsonEncode(_resourceScope(parameters)));
  }

  Future<Object?> resume(ClientCommandIntent intent) async {
    if (principalBinding != intent.principalBinding) {
      throw StateError('Command principal changed');
    }
    final parameters =
        (jsonDecode(intent.requestJson) as Map).cast<String, dynamic>();
    final stored = await pendingIntent(intent.operation, parameters);
    if (stored == null ||
        stored.commandId != intent.commandId ||
        stored.requestJson != intent.requestJson) {
      throw StateError('Pending intent changed');
    }
    final result = await invoke(
        intent.operation, {...parameters, 'p_command_id': intent.commandId});
    if (result is Map &&
        result['mutation'] is Map &&
        result['mutation']['commandId'] == intent.commandId &&
        (result['code'] == 200 ||
            result['status'] == 'rejected' ||
            result['status'] == 'conflict')) {
      await ClientCommandIdentity.completeIntent(
          intent.operation,
          {
            'principal': principalBinding,
            'operation': intent.operation,
            'parameters': parameters
          },
          commandId: intent.commandId,
          principalBinding: intent.principalBinding);
    }
    return result;
  }

  // Mechanical resource identities for the opted-in typed adapters. Version
  // preconditions and mutable contents stay in the immutable request, not scope.
  static Map<String, Object?> _resourceScope(Map<String, dynamic> parameters) {
    const ids = {
      'id',
      'occasion',
      'organization',
      'unit',
      'product_id',
      'occasion_link',
      'p_occasion',
      'p_order',
      'p_product_id',
      'p_ticket',
      'p_place',
      'p_group',
      'p_group_id',
      'p_form_id',
      'p_source_form_id',
      'p_pool',
      'p_unit',
      'p_resource',
      'p_occasion_link',
      'p_target_occasion_link'
    };
    final scope = <String, Object?>{};
    void collect(Map values, String path) {
      for (final entry in values.entries) {
        final key = entry.key.toString();
        if (ids.contains(key) && entry.value is! Map && entry.value is! List) {
          scope['$path/$key'] = entry.value;
        } else if (entry.value is Map &&
            {
              'p_group',
              'p_place',
              'p_information',
              'p_form',
              'p_blueprint',
              'p_product',
              'p_resource',
              'p_bundle',
              'pool',
              'p_target'
            }.contains(key)) {
          collect(entry.value as Map, '$path/$key');
        }
      }
    }

    collect(parameters, '');
    final keys = scope.keys.toList()..sort();
    return {for (final key in keys) key: scope[key]};
  }
}

class _PendingCommand {
  _PendingCommand(this.id, this.parameters);
  final String id;
  final Map<String, dynamic> parameters;
  Future<Object?>? inFlight;
}
