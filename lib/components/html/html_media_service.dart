import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:fstapp/components/images/db_images.dart';
import 'package:fstapp/components/images/image_control_client.dart';
import 'package:fstapp/components/images/image_upload_input.dart';
import 'package:fstapp/components/images/image_upload_limits.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'html_document_codec.dart';
import 'html_image_preview.dart';
export 'html_document_codec.dart' show HtmlContentProfile;

/// The destination scope is fixed when an editing session starts.
class HtmlMediaOwner {
  const HtmlMediaOwner.occasion(this.id) : isUnit = false;
  const HtmlMediaOwner.unit(this.id) : isUnit = true;
  const HtmlMediaOwner.none()
      : id = null,
        isUnit = false;
  final int? id;
  final bool isUnit;
  bool get canImport => id != null && id! > 0;
  Map<String, int> get requestFields {
    if (!canImport)
      throw StateError('Image import is unavailable in this scope');
    return {isUnit ? 'unitId' : 'occasionId': id!};
  }

  String get key => '${isUnit ? 'unit' : 'occasion'}:$id';
  @override
  bool operator ==(Object other) =>
      other is HtmlMediaOwner && other.id == id && other.isUnit == isUnit;
  @override
  int get hashCode => Object.hash(id, isUnit);
}

class HtmlMediaDraft {
  HtmlMediaDraft({
    Future<Uint8List> Function(String, HtmlMediaOwner)? fetch,
    Future<String> Function(Uint8List, HtmlMediaOwner)? upload,
    Future<bool> Function(String, HtmlMediaOwner)? owns,
  })  : _fetch = fetch ?? _fetchImage,
        _upload = upload ?? _uploadImage,
        _owns = owns ?? _ownsImage;

  static const maxImageBytes = ImageUploadLimits.maxInputBytes;
  static const maxPendingBytes = 32 * 1024 * 1024;
  static const _draftPrefix = 'https://html-draft.invalid/';
  final Future<Uint8List> Function(String, HtmlMediaOwner) _fetch;
  final Future<String> Function(Uint8List, HtmlMediaOwner) _upload;
  final Future<bool> Function(String, HtmlMediaOwner) _owns;
  final _assets = <String, _PendingImage>{};
  final _sources = <String, Future<String>>{};
  final _ownership = <String, Future<bool>>{};
  final _previews = <String, Future<Uint8List>>{};
  int _pendingBytes = 0;
  bool _disposed = false;
  Future<void> _decodeTail = Future.value();

  Uint8List? previewBytes(String source) => _assets[source]?.bytes;
  Future<Uint8List> previewSource(String source, HtmlMediaOwner owner) {
    if (!owner.canImport)
      return Future.error(StateError('Authorized preview is unavailable'));
    final key = '${owner.key}:$source';
    return _previews.putIfAbsent(key, () async {
      try {
        final staged = await importSource(source, owner);
        final bytes = previewBytes(staged);
        if (bytes != null) return bytes;
        final bounded = await addBytes(await _fetch(source, owner), owner);
        return previewBytes(bounded)!;
      } catch (_) {
        _previews.remove(key);
        rethrow;
      }
    });
  }

  bool get hasUnknownUploads => _assets.values.any((asset) => asset.unknown);
  bool hasUnknownUploadsIn(String html) => HtmlDocumentCodec.decode(html)
      .imageSlots
      .any((image) => _assets[image.source]?.unknown ?? false);
  void allowExplicitUnknownRetry() {
    for (final asset in _assets.values) {
      asset.unknown = false;
    }
  }

  Future<String> addBytes(Uint8List bytes, HtmlMediaOwner owner) async {
    if (_disposed) throw StateError('Media draft disposed');
    if (!owner.canImport)
      throw StateError('Image import is unavailable in this scope');
    try {
      ImageUploadLimits.checkByteLength(bytes.length);
    } on ImageUploadLimitExceeded catch (error) {
      throw StateError(error.message);
    }
    final inputKey = 'bytes:${owner.key}:${sha256.convert(bytes)}';
    final existing = _sources[inputKey];
    if (existing != null) return existing;
    final operation = _addBytes(bytes, owner);
    _sources[inputKey] = operation;
    try {
      return await operation;
    } catch (_) {
      _sources.remove(inputKey);
      rethrow;
    }
  }

  Future<String> _addBytes(Uint8List bytes, HtmlMediaOwner owner) async {
    if (_pendingBytes + bytes.length > maxPendingBytes)
      throw StateError('Pending images exceed 32 MiB');
    // Reserve before awaiting, so concurrent paste cannot exceed the budget.
    _pendingBytes += bytes.length;
    try {
      final previous = _decodeTail;
      final complete = Completer<void>();
      _decodeTail = complete.future;
      await previous;
      late Uint8List verified;
      try {
        verified = await _validateAndNormalize(bytes);
      } finally {
        complete.complete();
      }
      if (_disposed) throw StateError('Media draft disposed');
      final key =
          '$_draftPrefix${owner.isUnit ? 'unit' : 'occasion'}-${owner.id}/${sha256.convert(verified)}';
      if (_assets.containsKey(key)) {
        _pendingBytes -= bytes.length;
        return key;
      }
      if (_pendingBytes - bytes.length + verified.length > maxPendingBytes)
        throw StateError('Pending images exceed 32 MiB');
      _pendingBytes += verified.length - bytes.length;
      _assets[key] = _PendingImage(verified, owner);
      return key;
    } catch (_) {
      _pendingBytes -= bytes.length;
      rethrow;
    }
  }

  Future<String> importSource(String source, HtmlMediaOwner owner) async {
    if (source.startsWith(_draftPrefix)) {
      final asset = _assets[source];
      if (asset == null || asset.owner != owner)
        throw StateError('Unknown media draft or owner');
      return source;
    }
    if (!owner.canImport)
      throw StateError('Image import is unavailable in this scope');
    if (source.startsWith('data:')) {
      if (source.length > ImageUploadLimits.maxBase64Characters + 1024)
        throw StateError('Image exceeds 20 MB');
      return addBytes(UriData.parse(source).contentAsBytes(), owner);
    }
    final uri = Uri.tryParse(source);
    if (uri == null ||
        !uri.hasScheme ||
        uri.scheme != 'https' ||
        uri.host.isEmpty ||
        uri.userInfo.isNotEmpty) {
      throw StateError('Image requires a resolved HTTPS source');
    }
    final scoped = '${owner.key}:$source';
    try {
      if (await (_ownership[scoped] ??= _owns(source, owner))) return source;
    } catch (_) {
      _ownership.remove(scoped);
      rethrow;
    }
    final existing = _sources[scoped];
    if (existing != null) return existing;
    final operation =
        _fetch(source, owner).then((bytes) => addBytes(bytes, owner));
    _sources[scoped] = operation;
    try {
      return await operation;
    } catch (_) {
      _sources.remove(scoped);
      rethrow;
    }
  }

  /// Clipboard HTML enters the same parser and media draft as file selection.
  Future<String> importHtml(String html, HtmlMediaOwner owner) async {
    final draft = HtmlDocumentCodec.decode(html);
    for (final image in draft.imageSlots) {
      final source = image.source ?? image.attributes['data-src'];
      if (source == null || source.isEmpty)
        throw StateError('Image source is missing');
      draft.replaceImageSource(image.id, await importSource(source, owner));
      draft.removeImageAlternatives(image.id);
    }
    return draft.encode();
  }

  /// Parent save is the sole upload boundary. Successful uploads remain cached
  /// when the entity writer fails; unknown outcomes require an explicit retry.
  Future<String> prepareHtml(
      String html, String originalHtml, HtmlMediaOwner owner) async {
    if (html == originalHtml && !html.contains(_draftPrefix))
      return HtmlDocumentCodec.decode(html).encode();
    final originalImages =
        HtmlDocumentCodec.decode(originalHtml).imageSlots.toList();
    final originalSources = originalImages
        .map((image) => image.source ?? image.attributes['data-src'])
        .whereType<String>()
        .toSet();
    final draft = HtmlDocumentCodec.decode(html);
    for (final image in draft.imageSlots) {
      final source = image.source ?? image.attributes['data-src'];
      if (source == null || source.isEmpty) {
        if (originalImages.any((original) =>
            original.attributes.toString() == image.attributes.toString()))
          continue;
        throw StateError('Image source is missing');
      }
      if (originalSources.contains(source) && !source.startsWith(_draftPrefix))
        continue;
      final imported = await importSource(source, owner);
      final asset = _assets[imported];
      if (asset == null) continue; // Verified asset of this destination scope.
      if (asset.unknown)
        throw const ImageUploadOutcomeUnknown('Explicit retry required');
      if (asset.uploaded == null) {
        final upload = asset.uploading ??= _upload(asset.bytes, owner);
        try {
          asset.uploaded = await upload;
          _ownership['${owner.key}:${asset.uploaded}'] = Future.value(true);
        } on ImageUploadOutcomeUnknown {
          asset.unknown = true;
          rethrow;
        } finally {
          if (identical(asset.uploading, upload)) asset.uploading = null;
        }
      }
      draft.replaceImageSource(image.id, asset.uploaded!);
      // Do not keep a stale srcset pointing at the imported external source.
      // The editor mapper preserves existing attributes; media replacement
      // removes alternative external sources through the codec seam below.
      draft.removeImageAlternatives(image.id);
    }
    return draft.encode();
  }

  void dispose() {
    _disposed = true;
    _assets.clear();
    _sources.clear();
    _ownership.clear();
    _previews.clear();
  }
}

class _PendingImage {
  _PendingImage(this.bytes, this.owner);
  final Uint8List bytes;
  final HtmlMediaOwner owner;
  String? uploaded;
  Future<String>? uploading;
  bool unknown = false;
}

Future<Uint8List> _validateAndNormalize(Uint8List bytes) async {
  final heic = _isHeic(bytes);
  if (heic && kIsWeb) {
    throw const FormatException('HEIC image import is unavailable on web');
  }

  ui.Codec? codec;
  ui.Image? image;
  try {
    if (!heic) {
      final image = ImageUploadInput.inspect(bytes);
      final (width, height) = image.dimensions!;
      final longerEdge = width > height ? width : height;
      final scale = HtmlImagePreview.maxDecodeEdge / longerEdge;
      codec = await ui.instantiateImageCodec(
        bytes,
        targetWidth: scale < 1 ? (width * scale).round().clamp(1, width) : null,
        targetHeight: scale < 1 ? (height * scale).round().clamp(1, height) : null,
      );
    } else {
      // Native HEIC imports retain the platform decoder and normalize to PNG.
      final buffer = await ui.ImmutableBuffer.fromUint8List(bytes);
      ui.ImageDescriptor? descriptor;
      try {
        descriptor = await ui.ImageDescriptor.encoded(buffer);
        ImageUploadLimits.checkDimensions(descriptor.width, descriptor.height);
        codec = await descriptor.instantiateCodec();
      } finally {
        descriptor?.dispose();
        buffer.dispose();
      }
    }
    image = (await codec.getNextFrame()).image;
    if (!heic) return bytes;
    final normalized = await image.toByteData(format: ui.ImageByteFormat.png);
    if (normalized == null) throw StateError('Image normalization failed');
    final png = normalized.buffer.asUint8List();
    ImageUploadLimits.checkByteLength(png.length);
    return png;
  } on ImageUploadLimitExceeded catch (error) {
    throw StateError(error.message);
  } finally {
    image?.dispose();
    codec?.dispose();
  }
}

bool _isHeic(Uint8List bytes) {
  // ISO BMFF ftyp has a major brand at offset 8 and compatible brands
  // after its minor version. Inspect only the declared ftyp box.
  if (bytes.length < 16) return false;
  final data = ByteData.sublistView(bytes);
  if (data.getUint32(4) != 0x66747970) return false; // ftyp
  final end = data.getUint32(0);
  if (end < 16 || end > bytes.length) return false;
  const brands = {'heic', 'heix', 'hevc', 'hevx', 'mif1'};
  String brandAt(int offset) =>
      String.fromCharCodes(bytes.sublist(offset, offset + 4));
  if (brands.contains(brandAt(8))) return true;
  for (var offset = 16; offset + 4 <= end; offset += 4) {
    if (brands.contains(brandAt(offset))) return true;
  }
  return false;
}

Future<Uint8List> _fetchImage(String source, HtmlMediaOwner owner) async {
  final response = await Supabase.instance.client.functions.invoke(
      'fetch-http-data',
      body: {'targetUrl': source, ...owner.requestFields});
  if (response.status != 200 ||
      response.data is! Map ||
      response.data['data'] is! String) {
    throw StateError('Authorized image fetch failed');
  }
  final encoded = response.data['data'] as String;
  if (encoded.length > ImageUploadLimits.maxBase64Characters)
    throw StateError('Image exceeds 20 MB');
  return base64Decode(encoded);
}

Future<bool> _ownsImage(String source, HtmlMediaOwner owner) =>
    DbImages.isImageOwned(source,
        occasion: owner.isUnit ? null : owner.id,
        unit: owner.isUnit ? owner.id : null);
Future<String> _uploadImage(Uint8List bytes, HtmlMediaOwner owner) =>
    DbImages.uploadImage(
        bytes, owner.isUnit ? null : owner.id, owner.isUnit ? owner.id : null);
