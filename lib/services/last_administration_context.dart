import 'package:fstapp/services/storage_helper.dart';

/// A navigation preference, never an authorization decision. Keep it across
/// logout, scoped to the tenant and account, and recheck access before restoring.
class LastAdministrationContext {
  static final instance = LastAdministrationContext();

  LastAdministrationContext({
    Future<String?> Function(String)? read,
    Future<void> Function(String, String)? write,
    Future<void> Function(String)? remove,
  })  : _read = read ?? StorageHelper.get,
        _write = write ?? StorageHelper.set,
        _remove = remove ?? StorageHelper.remove;

  final Future<String?> Function(String) _read;
  final Future<void> Function(String, String) _write;
  final Future<void> Function(String) _remove;

  static String _key(int tenant, String user) =>
      'last-administration/v1/$tenant/$user';

  static bool canRestoreFor(String? path) =>
      path == null || path.isEmpty || path == '/' || path == '/login';

  static bool isValidPath(String path) =>
      RegExp(r'^/unit/[1-9][0-9]*/edit$').hasMatch(path) ||
      RegExp(r'^/[a-zA-Z0-9_-]+/(admin|reservations)$').hasMatch(path);

  Future<void> remember(int tenant, String? user, String path) async {
    if (user == null || user.isEmpty || !isValidPath(path)) return;
    try {
      await _write(_key(tenant, user), path);
    } catch (_) {
      // Unavailable browser/device storage must not prevent navigation.
    }
  }

  Future<String?> restore(int tenant, String? user,
      {required Future<bool> Function(String) canAccess}) async {
    if (user == null || user.isEmpty) return null;
    final key = _key(tenant, user);
    try {
      final path = await _read(key);
      if (path == null) return null;
      if (isValidPath(path) && await canAccess(path)) return path;
      await _remove(key);
    } catch (_) {
      // A transient network/storage error should not erase the preference.
    }
    return null;
  }
}
