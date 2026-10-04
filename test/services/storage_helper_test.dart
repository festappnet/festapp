import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:fstapp/services/storage_helper.dart';
import 'package:path/path.dart' as path;
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:sembast/sembast_io.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('offline string records survive replacement and reopening on disk',
      () async {
    final directory = await Directory.systemTemp.createTemp('festapp-storage-');
    final originalProvider = PathProviderPlatform.instance;
    PathProviderPlatform.instance = _DocumentsProvider(directory.path);
    const dbName = 'offline.db';
    final dbPath = path.join(directory.path, dbName);
    addTearDown(() async {
      PathProviderPlatform.instance = originalProvider;
      final db = await databaseFactoryIo.openDatabase(dbPath);
      await db.close();
      await directory.delete(recursive: true);
    });

    await StorageHelper.setAllAtomic({
      'generation/9/643/catalog/old.data': '{"title":"Původní program"}',
      'active/9/643/catalog': 'old',
      'profile.email': 'user@example.test',
      'obsolete': 'remove me',
    }, dbName);
    await StorageHelper.replaceByPrefixesAtomic({
      'generation/9/643/catalog/new.data': '{"title":"Nový program"}',
      'active/9/643/catalog': 'new',
      'obsolete': null,
    }, [
      'generation/9/643/catalog/'
    ], dbName);

    final db = await databaseFactoryIo.openDatabase(dbPath);
    await db.close();
    final reopened = await databaseFactoryIo.openDatabase(dbPath);
    try {
      final store = StoreRef.main();
      expect(await store.record('active/9/643/catalog').get(reopened), 'new');
      expect(await store.record('profile.email').get(reopened),
          'user@example.test');
      expect(
          await store.record('generation/9/643/catalog/new.data').get(reopened),
          '{"title":"Nový program"}');
      expect(
          await store.record('generation/9/643/catalog/old.data').get(reopened),
          isNull);
      expect(await store.record('obsolete').get(reopened), isNull);
    } finally {
      await reopened.close();
    }
  });
}

class _DocumentsProvider extends PathProviderPlatform {
  _DocumentsProvider(this.directory);

  final String directory;

  @override
  Future<String?> getApplicationDocumentsPath() async => directory;
}
