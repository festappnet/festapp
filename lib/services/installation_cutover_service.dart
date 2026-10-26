import 'package:fstapp/app_config.dart';
import 'package:fstapp/services/storage_helper.dart';

typedef CutoverRead = Future<String?> Function(String key, [String? database]);
typedef CutoverAtomicWrite =
    Future<void> Function(Map<String, String?> values, [String? database]);
typedef CutoverRemovePrefixes =
    Future<void> Function(List<String> prefixes, [String? database]);

/// Owns an optional, tenant-configured one-time installation migration.
///
/// The generation marker is written last. A crash before that point repeats
/// the idempotent cleanup and no old occasion cache is made visible.
class InstallationCutoverService {
  InstallationCutoverService({
    String? generation,
    CutoverRead? read,
    CutoverAtomicWrite? writeAtomic,
    CutoverRemovePrefixes? removePrefixes,
  }) : generation = generation ?? AppConfig.effectivePushAppGeneration,
       _read = read ?? StorageHelper.get,
       _writeAtomic = writeAtomic ?? StorageHelper.setAllAtomic,
       _removePrefixes = removePrefixes ?? StorageHelper.removeByPrefixesAtomic;

  static const markerKey = 'installation_generation';
  static const clientSyncDatabase = 'client_sync_v1.db';

  static const legacyKeys = <String>{
    'mySchedule',
    'events',
    'information',
    'activities',
    'userInventoryBundle',
    'speakers',
    'cleaningStatus',
    'eventFeedback',
    'lastSyncedAt',
    'selectedPlaceType',
    'user_info',
    'globalSettingsOffline',
    'occasionsOffline',
    'newsOffline',
    'places',
    'pathsOffline',
    'icons',
    'place_types',
  };

  final String generation;
  final CutoverRead _read;
  final CutoverAtomicWrite _writeAtomic;
  final CutoverRemovePrefixes _removePrefixes;

  /// Returns true only when this invocation performed the migration.
  Future<bool> run() async {
    if (generation.isEmpty) return false;
    if (await _read(markerKey) == generation) return false;

    // The public JM binary predates this store. Clearing pointers/generations
    // also safely handles development builds installed before this marker;
    // content-addressed blobs are harmless and may be reused after bootstrap.
    await _removePrefixes(const [
      'pointer/',
      'generation/',
      'context/',
    ], clientSyncDatabase);
    await _writeAtomic({
      for (final key in legacyKeys) key: null,
      markerKey: generation,
    });
    return true;
  }
}
