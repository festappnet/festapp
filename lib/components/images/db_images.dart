import 'dart:typed_data';
import 'package:fstapp/app_config.dart';
import 'package:fstapp/components/images/image_control_client.dart';
import 'image_file_format.dart';
import 'package:fstapp/database_tables/tb.dart';
import 'package:http/http.dart' as http;
import 'package:supabase_flutter/supabase_flutter.dart';

class DbImages {
  static final _supabase = Supabase.instance.client;
  static final _httpClient = http.Client();
  static const _bucketName = 'public-files';

  /// Detect image format from magic bytes and return extension.
  static String _detectExtension(Uint8List data) => ImageFileFormat.detect(data).extension;

  /// Upload an image to the shared Worker with optional server-side transform.
  ///
  /// The control API resolves the server-owned project registry from projectId.
  ///
  /// [imageData]   – raw image bytes.
  /// [occasion]    – occasion ID for permission check (mutually exclusive with [unit]).
  /// [unit]        – unit ID for permission check (mutually exclusive with [occasion]).
  /// [maxEdge]     – longer-edge limit in px (Worker default: 1200).
  /// [maxBytes]    – skip transform when file is smaller (Worker default: 800 KB).
  /// [quality]     – JPEG quality 1-100 (Worker default: 70, ignored for PNG).
  /// [endpoint] – explicit endpoint injection for tests.
  static Future<String> uploadImage(
    Uint8List imageData,
    int? occasion,
    int? unit, {
    int? maxEdge,
    int? maxBytes,
    int? quality,
    String? endpoint,
  }) async {
    final session = _supabase.auth.currentSession;
    if (session == null) throw Exception('Not authenticated');

    final ext = _detectExtension(imageData);
    return ImageControlClient(
      endpoint: endpoint ?? AppConfig.imageApiUrl,
      projectId: AppConfig.imageProjectId,
      httpClient: _httpClient,
    ).upload(
      bytes: imageData,
      filename: '${DateTime.now().millisecondsSinceEpoch}.$ext',
      accessToken: session.accessToken,
      occasionId: occasion,
      unitId: unit,
      maxEdge: maxEdge,
      maxBytes: maxBytes,
      quality: quality,
    );
  }

  static bool _isR2Url(String value) {
    final uri = Uri.tryParse(value);
    return uri?.scheme == 'https' &&
        (uri?.host == 'img.festapp.net' || uri?.host == 'a.img.festapp.net') &&
        uri!.path.startsWith('/images/');
  }

  static Future<void> removeImage(String imageUrl) async {
    if (_isR2Url(imageUrl)) {
      final token = _supabase.auth.currentSession!.accessToken;
      await ImageControlClient(
              endpoint: AppConfig.imageApiUrl,
              projectId: AppConfig.imageProjectId,
              httpClient: _httpClient)
          .deleteLinks([imageUrl], token);
    } else {
      // Supabase Storage: existing path extraction
      final uri = Uri.parse(imageUrl);
      final segments = uri.pathSegments;
      final bucketIndex = segments.indexOf(_bucketName);
      if (bucketIndex == -1 || bucketIndex + 1 >= segments.length) {
        throw Exception('Invalid image URL');
      }
      final filePath = segments.sublist(bucketIndex + 1).join('/');
      await _supabase.storage.from(_bucketName).remove([filePath]);
      await _supabase.rpc('remove_image_records', params: {
        'p_links': [imageUrl]
      });
    }
  }

  static Future<String> createCopyOfImage(
      String imageUrl, int? occasion, int? unit) async {
    if (_isR2Url(imageUrl)) {
      // R2: download the image bytes and re-upload via Worker
      final bytes = await ImageControlClient(
              endpoint: AppConfig.imageApiUrl,
              projectId: AppConfig.imageProjectId,
              httpClient: _httpClient)
          .download(imageUrl);
      return uploadImage(bytes, occasion, unit);
    }

    // Supabase Storage: existing copy logic
    final uri = Uri.parse(imageUrl);
    final segments = uri.pathSegments;
    final bucketIndex = segments.indexOf(_bucketName);
    if (bucketIndex == -1 || bucketIndex + 1 >= segments.length) {
      throw Exception('Invalid image URL');
    }
    final filePath = segments.sublist(bucketIndex + 1).join('/');

    final newPath = 'images/${DateTime.now().millisecondsSinceEpoch}.jpg';
    await _supabase.storage.from(_bucketName).copy(filePath, newPath);

    final newPublicUrl =
        _supabase.storage.from(_bucketName).getPublicUrl(newPath);

    await _supabase.rpc('add_image_record', params: {
      'p_link': newPublicUrl,
      'p_occasion_id': occasion,
      'p_unit_id': unit,
    });

    return newPublicUrl;
  }

  static Future<bool> isImageOwned(String imageUrl, {int? occasion, int? unit}) async {
    if ((occasion == null) == (unit == null)) throw ArgumentError('Exactly one image owner is required');
    final query = _supabase.from(Tb.images.table).select(Tb.images.id).eq(Tb.images.link, imageUrl);
    final response = await (occasion != null
      ? query.eq(Tb.images.occasion, occasion)
      : query.eq(Tb.images.unit, unit!));
    return response.isNotEmpty;
  }

  static Future<void> cleanupRemovedImages(
      List<String> removedImages, int occasion) async {
    if (removedImages.isEmpty) return;

    final response = await _supabase
        .from(Tb.images.table)
        .select()
        .inFilter(Tb.images.link, removedImages)
        .eq(Tb.images.occasion, occasion);

    // Partition URLs into R2 and Supabase Storage lists
    List<String> r2Links = [];
    List<String> supabasePaths = [];
    for (var image in response) {
      String imageUrl = image[Tb.images.link];
      if (_isR2Url(imageUrl)) {
        r2Links.add(imageUrl);
      } else {
        final uri = Uri.parse(imageUrl);
        final segments = uri.pathSegments;
        final bucketIndex = segments.indexOf(_bucketName);
        if (bucketIndex != -1 && bucketIndex + 1 < segments.length) {
          supabasePaths.add(segments.sublist(bucketIndex + 1).join('/'));
        }
      }
    }

    // One bounded, ownership-aware control request for the whole R2 batch.
    if (r2Links.isNotEmpty) {
      final token = _supabase.auth.currentSession!.accessToken;
      await ImageControlClient(
              endpoint: AppConfig.imageApiUrl,
              projectId: AppConfig.imageProjectId,
              httpClient: _httpClient)
          .deleteLinks(r2Links, token);
    }

    // Delete Supabase Storage images in batch
    if (supabasePaths.isNotEmpty) {
      await _supabase.storage.from(_bucketName).remove(supabasePaths);
    }

    final supabaseLinks =
        removedImages.where((link) => !_isR2Url(link)).toList();
    if (supabaseLinks.isNotEmpty) {
      await _supabase
          .rpc('remove_image_records', params: {'p_links': supabaseLinks});
    }
  }
}
