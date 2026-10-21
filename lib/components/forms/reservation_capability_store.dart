import 'dart:convert';
import 'package:uuid/uuid.dart';
import 'package:fstapp/services/storage_helper.dart';

typedef ReservationCapabilityRead = Future<String?> Function(String key);
typedef ReservationCapabilityWrite = Future<bool> Function(
    String key, String? expected, String? next);

/// A buyer capability only. No seat state or form/person data is persisted.
class ReservationCapability {
  const ReservationCapability(this.secret, this.expiresAt, this.generation);
  final String secret;
  final DateTime? expiresAt;
  final String generation;
  String get encoded => jsonEncode({
        'secret': secret,
        'expiresAt': expiresAt?.toUtc().toIso8601String(),
        'generation': generation,
      });
}

/// Uses the application's existing Sembast owner, including on Flutter web.
/// Conditional writes preserve a newer tab/session's capability on late replies.
class ReservationCapabilityStore {
  ReservationCapabilityStore({
    required String backend,
    required String formKey,
    ReservationCapabilityRead? read,
    ReservationCapabilityWrite? compareAndSet,
    DateTime Function()? now,
  })  : key = 'festapp:hold-capability:${jsonEncode([backend, formKey])}',
        _read = read ?? StorageHelper.get,
        _write = compareAndSet ?? StorageHelper.compareAndSetString,
        _now = now ?? DateTime.now;
  final String key;
  final ReservationCapabilityRead _read;
  final ReservationCapabilityWrite _write;
  final DateTime Function() _now;
  String? _raw;
  Future<void> _tail = Future.value();

  Future<T> _serialize<T>(Future<T> Function() operation) {
    final next = _tail.then((_) => operation());
    _tail = next.then<void>((_) {}, onError: (Object _) {});
    return next;
  }

  Future<ReservationCapability?> restore() => _serialize(() async {
        try {
          _raw = await _read(key);
          if (_raw == null) return null;
          final json = jsonDecode(_raw!) as Map<String, dynamic>;
          final secret = json['secret'];
          final generation = json['generation'];
          final expiresAt = json['expiresAt'] == null
              ? null
              : DateTime.tryParse(json['expiresAt'].toString());
          if (secret is! String ||
              secret.isEmpty ||
              generation is! String ||
              (json['expiresAt'] != null && expiresAt == null) ||
              (expiresAt != null && !expiresAt.isAfter(_now()))) {
            await _write(key, _raw, null);
            _raw = null;
            return null;
          }
          return ReservationCapability(secret, expiresAt, generation);
        } catch (_) {
          // Storage availability never prevents using an in-memory capability.
          return null;
        }
      });

  Future<ReservationCapability?> remember(String secret, DateTime? expiresAt) =>
      _serialize(() async {
        final capability =
            ReservationCapability(secret, expiresAt, const Uuid().v4());
        try {
          if (await _write(key, _raw, capability.encoded)) {
            _raw = capability.encoded;
            return capability;
          }
        } catch (_) {
          /* Existing storage can be unavailable in embedded browsers. */
        }
        return null;
      });

  Future<bool> clear(ReservationCapability? submitted) => _serialize(() async {
        if (submitted == null) return false;
        try {
          if (await _write(key, submitted.encoded, null)) {
            if (_raw == submitted.encoded) _raw = null;
            return true;
          }
        } catch (_) {/* The live SQL capability remains authoritative. */}
        return false;
      });
}
