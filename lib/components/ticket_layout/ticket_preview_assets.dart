import 'dart:ui' as ui;
import 'dart:convert';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:flutter/services.dart';

/// Generated from the PDF renderer's sources. Only immutable public assets
/// belong here; user resources always go through their authorized transport.
class TicketPreviewAssets {
  static const root = 'supabase/functions/_shared/ticket-assets/';
  final AssetBundle bundle;
  Future<Map<String, dynamic>>? _manifest;
  TicketPreviewAssets({AssetBundle? bundle}) : bundle = bundle ?? rootBundle;
  static final shared = TicketPreviewAssets();

  Future<Map<String, dynamic>> get manifest => _manifest ??= _read();
  Future<Map<String, dynamic>> _read() async {
    final raw =
        (await bundle.loadString('${root}preview-manifest.json')).trim();
    final value = jsonDecode(raw) as Map<String, dynamic>;
    final payload = '${raw.substring(0, raw.lastIndexOf(',"sha256":'))}}';
    if (value['schema'] != 1 ||
        value['generator'] != 1 ||
        sha256.convert(utf8.encode(payload)).toString() != value['sha256']) {
      throw const FormatException('Preview manifest integrity');
    }
    return value;
  }

  Future<Uint8List> bytes(Map entry) async {
    final file = entry['file'] as String;
    if (!RegExp(r'^(?:gallery-fonts/|backgrounds/)?[a-zA-Z0-9.-]+$')
        .hasMatch(file)) {
      throw const FormatException('Preview asset path');
    }
    final data = await bundle.load('$root$file');
    final bytes = data.buffer.asUint8List(
      data.offsetInBytes,
      data.lengthInBytes,
    );
    if (bytes.length != entry['byteLength'] ||
        sha256.convert(bytes).toString() != entry['sha256']) {
      throw const FormatException('Preview asset integrity');
    }
    return bytes;
  }

  Future<Map?> font(String id) async {
    final entry = (await manifest)['fonts'][id] as Map?;
    if (entry == null) return null;
    return {...entry, 'id': id, 'font': base64Encode(await bytes(entry))};
  }

  Future<Uint8List?> artwork(String url) async {
    final entry = (await manifest)['artwork'][url] as Map?;
    return entry == null ? null : bytes(entry);
  }
  final _decoded = <String,ui.Image>{};
  final _decoding = <String,Future<void>>{};
  int _decodedBytes = 0;
  static const _imageBudget = 24 * 1024 * 1024;
  /// The cache owns one handle; each session owns and disposes its clone.
  /// Eviction therefore never invalidates a canvas already using the image.
  Future<ui.Image?> image(String url) async {
    if((await manifest)['artwork'][url] == null) return null;
    while(true) {
      final hit=_decoded.remove(url);
      if(hit!=null) {_decoded[url]=hit;return hit.clone();}
      await _decoding.putIfAbsent(url,()=>_decode(url).whenComplete(() {_decoding.remove(url);}));
    }
  }
  Future<void> _decode(String url) async {
    final data=await artwork(url);
    final codec=await ui.instantiateImageCodec(data!);
    late final ui.Image image;
    try {image=(await codec.getNextFrame()).image;}finally{codec.dispose();}
    final size=image.width*image.height*4;
    if(size>_imageBudget){image.dispose();throw const FormatException('Preview image limit');}
    while(_decoded.isNotEmpty && (_decoded.length>=16 || _decodedBytes+size>_imageBudget)) {
      final key=_decoded.keys.first;
      final previous=_decoded.remove(key)!;
      _decodedBytes-=previous.width*previous.height*4;
      previous.dispose();
    }
    _decoded[url]=image;_decodedBytes+=size;
  }

}
