import 'dart:io';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fstapp/services/storage_helper.dart';
import 'resource_scope.dart';

/// Exclusive path-provider/default database scope. It refuses to replace
/// another fixture's handler and closes Sembast before removing its directory.
class LocalAppStorageFixture {
  LocalAppStorageFixture._(this.directory, this._scope);
  final Directory directory;
  final FixtureScope _scope;
  static Future<LocalAppStorageFixture> open() async {
    final scope = FixtureScope();
    final directory = await Directory.systemTemp.createTemp('festapp-fixture-');
    scope.onDispose(() => directory.delete(recursive: true));
    try {
      final messenger =
          TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
      const channel = MethodChannel('plugins.flutter.io/path_provider');
      if (!messenger.checkMockMessageHandler(channel.name, null)) {
        throw StateError('Path provider already belongs to another fixture');
      }
      Future<Object?> handler(MethodCall call) async => directory.path;
      messenger.setMockMethodCallHandler(channel, handler);
      scope.onDispose(() {
        if (!messenger.checkMockMessageHandler(channel.name, handler)) {
          throw StateError('Fixture path-provider handler was replaced');
        }
        messenger.setMockMethodCallHandler(channel, null);
      });
      scope.onDispose(() => StorageHelper.closeDatabase('default.db'));
      await StorageHelper.openDatabase();
      return LocalAppStorageFixture._(directory, scope);
    } catch (_) {
      await scope.dispose();
      rethrow;
    }
  }

  Future<void> dispose() => _scope.dispose();
}
