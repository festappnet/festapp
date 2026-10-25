import 'dart:convert';
import 'dart:typed_data';

/// An imported file's stable metadata and content, independent of OS providers.
/// Call [retain] while a temporary drag/picker provider is still available when
/// the file will be read later (for example after a confirmation dialog).
class ImportFile {
  ImportFile({
    required this.name,
    required Future<Uint8List> Function() readBytes,
    this.mimeType,
    Future<int?> Function()? size,
  }) : _readBytes = readBytes,
       _size = size;

  factory ImportFile.fromData(
    Uint8List bytes, {
    required String name,
    String? mimeType,
  }) {
    final copy = Uint8List.fromList(bytes);
    return ImportFile(
      name: name,
      mimeType: mimeType,
      readBytes: () async => copy,
      size: () async => copy.length,
    );
  }
  final String name;
  final String? mimeType;
  final Future<Uint8List> Function() _readBytes;
  final Future<int?> Function()? _size;
  Future<Uint8List>? _content;
  int? _knownLength;

  Future<Uint8List> readAsBytes() =>
      _content ??= Future.sync(_readBytes).then((bytes) {
        _knownLength = bytes.length;
        return bytes;
      });
  Future<String> readAsString({Encoding encoding = utf8}) async =>
      encoding.decode(await readAsBytes());
  Future<int> length() async {
    if (_knownLength != null) return _knownLength!;
    final size = await _size?.call();
    return size ?? (await readAsBytes()).length;
  }

  Future<ImportFile> retain() async {
    await readAsBytes();
    return this;
  }
}
