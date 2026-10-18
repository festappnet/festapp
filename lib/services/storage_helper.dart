import 'bounded_database_opener.dart';
import 'package:flutter/foundation.dart';
import 'package:sembast/sembast_io.dart';
import 'package:sembast_web/sembast_web.dart';
import 'package:path/path.dart';
import 'package:path_provider/path_provider.dart';

class StorageHelper {
  static final _opener = BoundedDatabaseOpener(open: (path) async {
    final fullPath = await _constructDbPath(path);
    return _databaseFactory.openDatabase(fullPath);
  });

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
    return _opener.get(path);
  }

  static Future<void> closeDatabase(String dbPath) => _opener.close(dbPath);

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
    final store = StoreRef.main();
    final db = await openDatabase(dbPath);
    final keys =
        removePrefixes.isEmpty ? const <Object?>[] : await store.findKeys(db);
    await db.transaction((transaction) async {
      for (final key in keys.whereType<String>().where(
          (key) => removePrefixes.any((prefix) => key.startsWith(prefix)))) {
        await store.record(key).delete(transaction);
      }
      for (final entry in values.entries) {
        if (entry.value == null) {
          await store.record(entry.key).delete(transaction);
        } else {
          await store.record(entry.key).put(transaction, entry.value!);
        }
      }
    });
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
