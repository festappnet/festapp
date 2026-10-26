import 'package:cross_file/cross_file.dart';
import 'package:cross_file_web/cross_file_web.dart';

XFile fileFromUri(Uri uri) => ScopedStorageXFile.fromCreationParams(
  WebScopedStorageXFileCreationParams.fromObjectUrl(objectUrl: uri.toString()),
);
