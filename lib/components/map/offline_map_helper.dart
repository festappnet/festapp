import 'dart:io';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:fstapp/components/map/offline_map_file_downloader.dart';
import 'package:fstapp/services/app_logger.dart';
import 'package:path_provider/path_provider.dart';

class OfflineMapHelper {
  /// Universal method: Checks if a file exists locally.
  /// If it exists, returns it; otherwise, if connectivity is available,
  /// downloads the file from [url] to [filePath] (reporting progress via [onProgress]).
  /// If no connectivity is available or the download fails, returns null.
  static Future<File?> getOrDownloadFile(
    String url,
    String filePath,
    Function(double) onProgress, {
    bool forceRefresh = false,
    bool allowDownload = true,
  }) async {
    final file = File(filePath);
    if (await file.exists() && !forceRefresh) {
      return file;
    }
    if (!allowDownload) return await file.exists() ? file : null;
    final connectivity = await Connectivity().checkConnectivity();
    if (connectivity.contains(ConnectivityResult.none)) {
      return null;
    }
    final downloader = OfflineMapFileDownloader();
    try {
      return await downloader.download(
        uri: Uri.parse(url),
        destination: file,
        onProgress: onProgress,
      );
    } catch (e) {
      AppLogger.error('Offline map download failed: $e');
      return null;
    } finally {
      downloader.close();
    }
  }

  /// Computes the local file path for the offline MBTiles package,
  /// deleting any old .mbtiles files not matching the current file name.
  static Future<String> getOfflinePackagePath(
      String offlineMapPackageURL) async {
    final directory = await getApplicationDocumentsDirectory();
    String fileName = Uri.parse(offlineMapPackageURL).pathSegments.last;
    String filePath = "${directory.path}/$fileName";
    final dirList = directory.listSync();
    for (var entity in dirList) {
      if (entity is File &&
          entity.path.endsWith(".mbtiles") &&
          entity.path != filePath) {
        await entity.delete();
      }
    }
    return filePath;
  }

  /// Computes the local file path for the style JSON,
  /// deleting any old .json files not matching the current file name.
  static Future<String> getOfflineStyleFilePath(String styleURL) async {
    final directory = await getApplicationDocumentsDirectory();
    String fileName = Uri.parse(styleURL).pathSegments.last;
    String filePath = "${directory.path}/$fileName";
    final dirList = directory.listSync();
    for (var entity in dirList) {
      if (entity is File &&
          entity.path.endsWith(".json") &&
          entity.path != filePath) {
        await entity.delete();
      }
    }
    return filePath;
  }

  /// Retrieves (or downloads if available) the offline MBTiles package.
  static Future<File?> getOfflineMapPackage(
      String offlineMapPackageURL, String filePath, Function(double) onProgress,
      {bool forceRefresh = false, bool allowDownload = true}) async {
    return getOrDownloadFile(
      offlineMapPackageURL,
      filePath,
      onProgress,
      forceRefresh: forceRefresh,
      allowDownload: allowDownload,
    );
  }

}
