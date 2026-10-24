import 'package:fstapp/data_services/client_sync/sembast_client_sync_storage.dart';
import 'package:flutter/foundation.dart';
import 'package:sembast/sembast_io.dart';
import 'package:sembast_web/sembast_web.dart';
import 'package:path/path.dart';
import 'package:path_provider/path_provider.dart';

class StorageHelper {
  static final Map<String, Database> _databases = {};

  static DatabaseFactory get _databaseFactory {
    return kIsWeb ? databaseFactoryWeb : databaseFactoryIo;
  }

  static Future<String> _constructDbPath(String dbPath) async {
    if (kIsWeb) {
      return dbPath;
    } else {
      final dir = await getApplicationDocumentsDirectory();
      await dir.create(recursive: true);
      return join(dir.path, dbPath);
    }
  }

  static Future<Database> openDatabase([String? dbPath]) async {
    final path = dbPath ?? 'default.db';
    if (!_databases.containsKey(path)) {
      final fullPath = await _constructDbPath(path);
      _databases[path] = await _databaseFactory.openDatabase(fullPath);
    }
    return _databases[path]!;
  }

  static Future<String?> get(String key, [String? dbPath]) async {
    final store = StoreRef.main();
    final db = await openDatabase(dbPath);
    return await store.record(key).get(db) as String?;
  }

  static Future<void> set(String key, String value, [String? dbPath]) async {
    final store = StoreRef.main();
    final db = await openDatabase(dbPath);
    await store.record(key).put(db, value);
  }

  static Future<void> remove(String key, [String? dbPath]) async {
    final store = StoreRef.main();
    final db = await openDatabase(dbPath);
    await store.record(key).delete(db);
  }

  /// Applies a group of string writes as one Sembast transaction.
  ///
  /// A null value deletes the key. This is the primitive used by the client
  /// sync store to make generation-pointer activation old-or-new after a
  /// crash; callers must stage and validate payloads before invoking it.
  static Future<void> setAllAtomic(Map<String, String?> values,
      [String? dbPath]) async {
    await replaceByPrefixesAtomic(values, const [], dbPath);
  }

  /// Applies writes and removes matching key families in one transaction.
  /// Prefix removals happen before writes so a replacement may reuse a key.
  static Future<void> replaceByPrefixesAtomic(
    Map<String, String?> values,
    List<String> removePrefixes, [
    String? dbPath,
  ]) async {
    await SembastClientSyncStorage(() => openDatabase(dbPath))
        .replaceAtomic(values, removePrefixes: removePrefixes);
  }

  /// Close one connection owned by this runtime before deleting its directory.
  /// Callers must first stop consumers of that database.
  static Future<void> closeDatabase(String dbPath) async {
    final database = _databases.remove(dbPath);
    await database?.close();
  }

  static Future<List<String>> keys([String? dbPath]) async {
    final store = StoreRef.main();
    final db = await openDatabase(dbPath);
    return (await store.findKeys(db))
        .whereType<String>()
        .toList(growable: false);
  }

  /// Removes several key families in one database transaction.
  static Future<void> removeByPrefixesAtomic(List<String> prefixes,
      [String? dbPath]) async {
    final store = StoreRef.main();
    final db = await openDatabase(dbPath);
    final keys = await store.findKeys(db);
    await db.transaction((transaction) async {
      for (final key in keys
          .whereType<String>()
          .where((key) => prefixes.any((prefix) => key.startsWith(prefix)))) {
        await store.record(key).delete(transaction);
      }
    });
  }
}
