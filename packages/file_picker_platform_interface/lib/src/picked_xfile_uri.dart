import 'package:cross_file/cross_file.dart';

XFile fileFromUri(Uri uri) => uri.scheme == 'file'
    ? XFile.fileSystem(path: uri.toFilePath())
    : XFile.scopedStorage(uri: uri.toString());
