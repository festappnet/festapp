import 'dart:io';
import 'package:crypto/crypto.dart';
import 'package:festapp_core/map.dart';

Future<void> verifyOfflineMapBundle(
    OfflineMapBundleManifest manifest, Directory directory) async {
  for (final asset in manifest.assets) {
    final file = File('${directory.path}/${asset.path}');
    if (!await file.exists()) {
      throw OfflineMapBundleException('Missing bundle file: ${asset.path}.');
    }
    if (await file.length() != asset.bytes) {
      throw OfflineMapBundleException('Size mismatch: ${asset.path}.');
    }
    final digest = await sha256.bind(file.openRead()).first;
    if (digest.toString() != asset.sha256) {
      throw OfflineMapBundleException('Checksum mismatch: ${asset.path}.');
    }
  }
}
