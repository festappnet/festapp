import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:fstapp/services/storage_helper.dart';
import 'package:uuid/uuid.dart';
import 'package:sembast/sembast.dart';

/// Immutable recovery handle. Original parameters include original revisions;
/// resuming never reads a fresh editor baseline or allocates another command ID.
class ClientCommandIntent {
  const ClientCommandIntent({
    required this.operation,
    required this.commandId,
    required this.principalBinding,
    required this.requestJson,
  });
  final String operation;
  final String commandId;
  final String principalBinding;
  final String requestJson;
}

class ClientCommandIdentity {
  static const _storageKey = 'client_command_client_id';
  static const _legacyFeedbackKey = 'event_feedback_client_id';

  static String fingerprint(Object? value) =>
      sha256.convert(utf8.encode(jsonEncode(_canonicalize(value)))).toString();

  // These formats are persisted recovery contracts, including payment intents.
  static String _pendingKey(String namespace, Object? payload) =>
      'client_command_pending:$namespace:${fingerprint(payload)}';

  static String _activeKey(
    String namespace,
    String? principalBinding,
    String scopeBinding,
  ) =>
      'client_command_active:$namespace:${fingerprint([
            principalBinding,
            scopeBinding
          ])}';

  static String newCommandId() => const Uuid().v4();

  static Future<String> claimIntent(
    String namespace,
    Object? payload, {
    String? principalBinding,
    String? scopeBinding,
    String? requestJson,
  }) async {
    final key = _pendingKey(namespace, payload);
    final activeKey = scopeBinding == null
        ? null
        : _activeKey(namespace, principalBinding, scopeBinding);
    final db = await StorageHelper.openDatabase();
    return db.transaction((transaction) async {
      final store = StoreRef.main();
      var commandId = await store.record(key).get(transaction) as String?;
      if (principalBinding != null) {
        final previousBinding =
            await store.record('$key:principal').get(transaction);
        if (commandId != null && previousBinding != principalBinding) {
          throw StateError('PAYMENT_RECOVERY_PRINCIPAL_CHANGED');
        }
        await store.record('$key:principal').put(transaction, principalBinding);
      }
      if (activeKey != null) {
        final active = await store.record(activeKey).get(transaction);
        if (active is Map && active['commandId'] != commandId) {
          throw StateError('CLIENT_COMMAND_PENDING_REQUIRES_RECOVERY');
        }
      }
      if (commandId == null || commandId.isEmpty) {
        commandId = newCommandId();
        await store.record(key).put(transaction, commandId);
        await store
            .record('$key:preconditions')
            .put(transaction, _expectedRevisions(payload));
      }
      if (activeKey != null) {
        await store.record(activeKey).put(transaction, {
          'commandId': commandId,
          'principal': principalBinding,
          'pendingKey': key,
        });
        await store.record('$key:scope').put(transaction, activeKey);
      }
      if (requestJson != null) {
        await store.record('$key:request').put(
              transaction,
              jsonEncode(_canonicalize(jsonDecode(requestJson))),
            );
      }
      return commandId;
    });
  }

  /// A terminal response may clear only the intent that produced it.
  /// The transaction prevents an old response from deleting a later claim.
  static Future<bool> completeIntent(
    String namespace,
    Object? payload, {
    required String commandId,
    required String principalBinding,
  }) async {
    final key = _pendingKey(namespace, payload);
    final db = await StorageHelper.openDatabase();
    return db.transaction((transaction) async {
      final store = StoreRef.main();
      if (await store.record(key).get(transaction) != commandId ||
          await store.record('$key:principal').get(transaction) !=
              principalBinding) {
        return false;
      }
      final activeKey = await store.record('$key:scope').get(transaction);
      if (activeKey is String) {
        final active = await store.record(activeKey).get(transaction);
        if (active is Map &&
            active['commandId'] == commandId &&
            active['principal'] == principalBinding) {
          await store.record(activeKey).delete(transaction);
        }
      }
      await store.record('$key:scope').delete(transaction);
      await store.record('$key:request').delete(transaction);
      await store.record(key).delete(transaction);
      await store.record('$key:principal').delete(transaction);
      await store.record('$key:preconditions').delete(transaction);
      return true;
    });
  }

  static Future<ClientCommandIntent?> pendingIntent(
    String operation, {
    required String principalBinding,
    required String scopeBinding,
  }) async {
    final activeKey = _activeKey(operation, principalBinding, scopeBinding);
    final db = await StorageHelper.openDatabase();
    return db.transaction((transaction) async {
      final store = StoreRef.main();
      final active = await store.record(activeKey).get(transaction);
      if (active is! Map ||
          active['principal'] != principalBinding ||
          active['pendingKey'] is! String) {
        return null;
      }
      final key = active['pendingKey'] as String;
      final id = await store.record(key).get(transaction);
      final principal = await store.record('$key:principal').get(transaction);
      final request = await store.record('$key:request').get(transaction);
      if (id != active['commandId'] ||
          principal != principalBinding ||
          request is! String) {
        return null;
      }
      return ClientCommandIntent(
        operation: operation,
        commandId: id as String,
        principalBinding: principalBinding,
        requestJson: request,
      );
    });
  }

  static Future<String> clientId() async {
    final db = await StorageHelper.openDatabase();
    return db.transaction((transaction) async {
      final store = StoreRef.main();
      var id = await store.record(_storageKey).get(transaction) as String?;
      id ??= await store.record(_legacyFeedbackKey).get(transaction) as String?;
      if (id == null || id.isEmpty) id = const Uuid().v4();
      await store.record(_storageKey).put(transaction, id);
      return id;
    });
  }

  /// Released order replacements stored only a payload digest, not its bytes.
  /// They can be resumed only when the original form values are supplied again.
  /// Never let a new replacement silently bypass an uncertain legacy intent.
  static Future<String?> pendingLegacyOrderReplacement(Object payload,
      {required String principalBinding}) async {
    const namespace = 'ticket_order_replace';
    final exactKey = _pendingKey(namespace, payload);
    final db = await StorageHelper.openDatabase();
    return db.transaction((transaction) async {
      final store = StoreRef.main();
      final keys = await store.findKeys(transaction);
      String? exact;
      for (final key in keys.whereType<String>().where((key) =>
          key.startsWith('client_command_pending:$namespace:') &&
          !key
              .substring('client_command_pending:$namespace:'.length)
              .contains(':'))) {
        if (await store.record('$key:principal').get(transaction) !=
            principalBinding) continue;
        final id = await store.record(key).get(transaction);
        if (id is! String || id.isEmpty) continue;
        if (key != exactKey)
          throw StateError('LEGACY_ORDER_RECOVERY_REQUIRES_ORIGINAL_INPUT');
        exact = id;
      }
      return exact;
    });
  }

  // Original version controls survive transport/process loss without persisting
  // customer payloads. The key's digest binds the entire normalized request.
  static Map<String, Object?> _expectedRevisions(
    Object? value, [
    String path = '',
  ]) {
    final result = <String, Object?>{};
    if (value is Map) {
      for (final entry in value.entries) {
        final key = entry.key.toString();
        final next = '$path/$key';
        if (((key.toLowerCase().contains('expected') &&
                    (key.toLowerCase().contains('version') ||
                        key.toLowerCase().contains('revision'))) ||
                key.toLowerCase().endsWith('revision')) &&
            (entry.value == null ||
                entry.value is num ||
                entry.value is String ||
                entry.value is Map)) {
          result[next] = entry.value;
        } else {
          result.addAll(_expectedRevisions(entry.value, next));
        }
      }
    } else if (value is List) {
      for (var i = 0; i < value.length; i++) {
        result.addAll(_expectedRevisions(value[i], '$path/$i'));
      }
    }
    return result;
  }

  static Object? _canonicalize(Object? value) {
    if (value is Map) {
      final entries = value.entries
          .map(
            (entry) =>
                MapEntry(entry.key.toString(), _canonicalize(entry.value)),
          )
          .toList()
        ..sort((left, right) => left.key.compareTo(right.key));
      return {for (final entry in entries) entry.key: entry.value};
    }
    if (value is Iterable) return value.map(_canonicalize).toList();
    return value;
  }
}
