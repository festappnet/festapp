import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:fstapp/services/storage_helper.dart';
import 'package:uuid/uuid.dart';
import 'package:sembast/sembast.dart';

class ClientCommandIdentity {
  static const _storageKey = 'client_command_client_id';
  static const _legacyFeedbackKey = 'event_feedback_client_id';

  static String fingerprint(Object? value) =>
      sha256.convert(utf8.encode(jsonEncode(_canonicalize(value)))).toString();

  static String newCommandId() => const Uuid().v4();

  static Future<String> claimIntent(
    String namespace,
    Object? payload, {
    String? principalBinding,
  }) async {
    final fingerprint = sha256
        .convert(utf8.encode(jsonEncode(_canonicalize(payload))))
        .toString();
    final key = 'client_command_pending:$namespace:$fingerprint';
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
      if (commandId == null || commandId.isEmpty) {
        commandId = newCommandId();
        await store.record(key).put(transaction, commandId);
      }
      return commandId;
    });
  }

  static Future<void> completeIntent(
    String namespace,
    Object? payload,
  ) async {
    final fingerprint = sha256
        .convert(utf8.encode(jsonEncode(_canonicalize(payload))))
        .toString();
    await StorageHelper.setAllAtomic({
      'client_command_pending:$namespace:$fingerprint': null,
      'client_command_pending:$namespace:$fingerprint:principal': null,
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

  static Object? _canonicalize(Object? value) {
    if (value is Map) {
      final entries = value.entries
          .map((entry) => MapEntry(
                entry.key.toString(),
                _canonicalize(entry.value),
              ))
          .toList()
        ..sort((left, right) => left.key.compareTo(right.key));
      return {for (final entry in entries) entry.key: entry.value};
    }
    if (value is Iterable) return value.map(_canonicalize).toList();
    return value;
  }
}
