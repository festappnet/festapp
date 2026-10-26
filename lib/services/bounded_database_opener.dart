import 'dart:async';

import 'package:sembast/sembast.dart';

class StorageOpenTimeoutException extends TimeoutException {
  StorageOpenTimeoutException(Duration duration)
      : super('Local database did not open in time', duration);
}

/// Bounds opening only. No caller receives a database or starts a transaction
/// after its opener times out. One pending opener owns each path until cleanup.
class BoundedDatabaseOpener {
  final Future<Database> Function(String) open;
  final Duration timeout;
  final _databases = <String, Database>{};
  final _pending = <String, Future<Database>>{};

  BoundedDatabaseOpener({
    required this.open,
    this.timeout = const Duration(seconds: 5),
  });

  Future<Database> get(String path) {
    final database = _databases[path];
    if (database != null) return Future.value(database);
    return _pending.putIfAbsent(path, () => _openBounded(path));
  }

  Future<void> close(String path) async {
    final pending = _pending[path];
    if (pending != null) {
      try {
        await pending;
      } catch (_) {/* Failed opens own late cleanup. */}
    }
    await _databases.remove(path)?.close();
  }

  Future<Database> _openBounded(String path) {
    var expired = false;
    final opening =
        Future<Database>.sync(() => open(path)).then((database) async {
      if (expired) {
        // Keep the failed slot until this handle is closed. A second opener
        // must never hand out a handle that this late completion then closes.
        try {
          await database.close();
        } finally {
          _pending.remove(path);
        }
      } else {
        _databases[path] = database;
        _pending.remove(path);
      }
      return database;
    }, onError: (Object error, StackTrace stack) {
      _pending.remove(path);
      Error.throwWithStackTrace(error, stack);
    });
    return opening.timeout(timeout, onTimeout: () {
      expired = true;
      throw StorageOpenTimeoutException(timeout);
    });
  }
}
