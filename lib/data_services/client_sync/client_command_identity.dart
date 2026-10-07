import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:fstapp/services/storage_helper.dart';
import 'package:uuid/uuid.dart';

class ClientCommandIdentity {
  static const _storageKey = 'client_command_client_id';
  static const _legacyFeedbackKey = 'event_feedback_client_id';

  static String fingerprint(Object? value) =>
      sha256.convert(utf8.encode(jsonEncode(_canonicalize(value)))).toString();

  static String newCommandId() => const Uuid().v4();

  static Future<String> claimIntent(
    String namespace,
    Object? payload,
  ) async {
    final fingerprint = sha256
        .convert(utf8.encode(jsonEncode(_canonicalize(payload))))
        .toString();
    final key = 'client_command_pending:$namespace:$fingerprint';
    var commandId = await StorageHelper.get(key);
    if (commandId == null || commandId.isEmpty) {
      commandId = newCommandId();
      await StorageHelper.set(key, commandId);
    }
    return commandId;
  }

  static Future<void> completeIntent(
    String namespace,
    Object? payload,
  ) async {
    final fingerprint = sha256
        .convert(utf8.encode(jsonEncode(_canonicalize(payload))))
        .toString();
    await StorageHelper.remove(
      'client_command_pending:$namespace:$fingerprint',
    );
  }

  static Future<String> clientId() async {
    var id = await StorageHelper.get(_storageKey);
    id ??= await StorageHelper.get(_legacyFeedbackKey);
    if (id == null || id.isEmpty) {
      id = const Uuid().v4();
    }
    await StorageHelper.set(_storageKey, id);
    return id;
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
