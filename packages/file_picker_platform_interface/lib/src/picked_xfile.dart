import 'dart:convert';
import 'dart:typed_data';
import 'package:cross_file/cross_file.dart';
import 'package:cross_file_platform_interface/cross_file_platform_interface.dart';
import 'picked_xfile_uri.dart'
    if (dart.library.js_interop) 'picked_xfile_uri_web.dart'
    as platform;

/// Preserve picker metadata and preloaded bytes over cross_file's provider API.
XFile pickedXFile(Uri uri, {required String name, Uint8List? bytes}) =>
    _PickedXFile(_PickedPlatformFile(uri, name, bytes));

final class _PickedXFile extends XFile {
  const _PickedXFile(super.platform);
}

final class _PickedPlatformFile extends PlatformXFile {
  _PickedPlatformFile(Uri uri, this.fileName, Uint8List? bytes)
    : content = bytes == null ? null : Uint8List.fromList(bytes),
      sourceUri = uri,
      super(PlatformXFileCreationParams(uri: uri.toString()));
  final Uri sourceUri;
  final String fileName;
  final Uint8List? content;
  late final XFile source = platform.fileFromUri(sourceUri);
  @override
  Future<String> name() async => fileName;
  @override
  Future<bool> exists() async => content != null || await source.exists();
  @override
  Future<int?> length() async => content?.length ?? await source.length();
  @override
  Future<DateTime?> lastModified() async =>
      content == null ? await source.lastModified() : null;
  @override
  Future<Uint8List> readAsBytes() async =>
      content ?? await source.readAsBytes();
  @override
  Future<String> readAsString({Encoding encoding = utf8}) async =>
      encoding.decode(await readAsBytes());
  @override
  Stream<Uint8List> openRead([int? start, int? end]) async* {
    final bytes = content;
    if (bytes == null) {
      yield* source.openRead(start, end);
    } else {
      final first = (start ?? 0).clamp(0, bytes.length);
      final last = (end ?? bytes.length).clamp(first, bytes.length);
      yield Uint8List.sublistView(bytes, first, last);
    }
  }
}
