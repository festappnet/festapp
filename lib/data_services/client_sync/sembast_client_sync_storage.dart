import 'package:festapp_core/sync.dart';
import 'package:sembast/sembast.dart';

/// The composition root owns the connection; this adapter only borrows it.
class SembastClientSyncStorage implements ClientSyncStorage {
  const SembastClientSyncStorage(this._database);
  final Future<Database> Function() _database;

  @override
  Future<String?> get(String key) async =>
      await StoreRef.main().record(key).get(await _database()) as String?;

  @override
  Future<List<String>> keys() async =>
      (await StoreRef.main().findKeys(await _database()))
          .whereType<String>()
          .toList(growable: false);

  @override
  Future<void> replaceAtomic(Map<String, String?> writes,
      {List<String> removePrefixes = const []}) async {
    final database = await _database();
    final store = StoreRef.main();
    final keys = removePrefixes.isEmpty
        ? const <Object?>[]
        : await store.findKeys(database);
    await database.transaction((transaction) async {
      for (final key in keys.whereType<String>().where(
          (key) => removePrefixes.any((prefix) => key.startsWith(prefix)))) {
        await store.record(key).delete(transaction);
      }
      for (final entry in writes.entries) {
        if (entry.value == null) {
          await store.record(entry.key).delete(transaction);
        } else {
          await store.record(entry.key).put(transaction, entry.value!);
        }
      }
    });
  }
}
