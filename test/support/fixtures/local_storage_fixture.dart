import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:fstapp/services/storage_helper.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';

/// Own a real disposable command journal and restore the platform singleton.
void registerLocalStorageFixture() {
  late Directory directory;
  late PathProviderPlatform previous;
  setUpAll(() async {
    directory =
        await Directory.systemTemp.createTemp('festapp-command-fixture-');
    previous = PathProviderPlatform.instance;
    PathProviderPlatform.instance = _Documents(directory.path);
  });
  tearDownAll(() async {
    await StorageHelper.closeDatabase('default.db');
    PathProviderPlatform.instance = previous;
    await directory.delete(recursive: true);
  });
}

class _Documents extends PathProviderPlatform {
  _Documents(this.path);
  final String path;
  @override
  Future<String?> getApplicationDocumentsPath() async => path;
}
