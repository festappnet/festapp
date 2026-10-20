import 'dart:typed_data';
import 'package:fstapp/app_config.dart';
import 'package:fstapp/components/images/image_control_client.dart';
import 'image_file_format.dart';
export 'image_upload_profile.dart';
import 'package:fstapp/database_tables/tb.dart';
import 'package:http/http.dart' as http;
import 'package:supabase_flutter/supabase_flutter.dart';

class DbImages {
  static final _supabase = Supabase.instance.client;
  static final _httpClient = http.Client();

  /// Upload original image bytes. The Worker owns all processing rules.
  ///
  /// The control API resolves the server-owned project registry from projectId.
  ///
  /// [imageData]   – raw image bytes.
  /// [occasion]    – occasion ID for permission check (mutually exclusive with [unit]).
  /// [unit]        – unit ID for permission check (mutually exclusive with [occasion]).
  /// [profile] – purpose-specific server processing, standard by default.
  /// [endpoint] – explicit endpoint injection for tests.
  static Future<String> uploadImage(
    Uint8List imageData,
    int? occasion,
    int? unit, {
    ImageUploadProfile profile = ImageUploadProfile.standard,
    String? endpoint,
  }) async => (await uploadImageWithResult(imageData, occasion, unit,
      profile: profile, endpoint: endpoint)).url;


  static Future<ImageUploadResult> uploadImageWithResult(
    Uint8List imageData,
    int? occasion,
    int? unit, {
    ImageUploadProfile profile = ImageUploadProfile.standard,
    String? endpoint,
  }) async {
    final session = _supabase.auth.currentSession;
    if (session == null) throw Exception('Not authenticated');

    final ext = ImageFileFormat.detect(imageData,
        allowSvg: profile == ImageUploadProfile.blueprintBackground).extension;
    return ImageControlClient(
      endpoint: endpoint ?? AppConfig.imageApiUrl,
      projectId: AppConfig.imageProjectId,
      httpClient: _httpClient,
    ).uploadWithResult(
      bytes: imageData,
      filename: '${DateTime.now().millisecondsSinceEpoch}.$ext',
      accessToken: session.accessToken,
      occasionId: occasion,
      unitId: unit,
      profile: profile,
    );
  }

  static bool _isR2Url(String value) {
    final uri = Uri.tryParse(value);
    return uri?.scheme == 'https' &&
        (uri?.host == 'img.festapp.net' || uri?.host == 'a.img.festapp.net') &&
        (uri!.path.startsWith('/images/') || uri.path.startsWith('/assets/'));
  }

  static Future<void> removeImage(String imageUrl) async {
    if (!_isR2Url(imageUrl)) throw ArgumentError('Invalid canonical asset URL');
    final token = _supabase.auth.currentSession!.accessToken;
    await ImageControlClient(
            endpoint: AppConfig.imageApiUrl,
            projectId: AppConfig.imageProjectId,
            httpClient: _httpClient)
        .deleteLinks([imageUrl], token);
  }

  static Future<String> createCopyOfImage(
      String imageUrl, int? occasion, int? unit) async {
    // Copies and uploads share the canonical Worker writer.
    final bytes = await ImageControlClient(
            endpoint: AppConfig.imageApiUrl,
            projectId: AppConfig.imageProjectId,
            httpClient: _httpClient)
        .download(imageUrl);
    return uploadImage(bytes, occasion, unit);
  }

  static Future<bool> isImageOwned(String imageUrl, {int? occasion, int? unit}) async {
    if ((occasion == null) == (unit == null)) throw ArgumentError('Exactly one image owner is required');
    final query = _supabase.from(Tb.images.table).select(Tb.images.id).eq(Tb.images.link, imageUrl);
    final response = await (occasion != null
      ? query.eq(Tb.images.occasion, occasion)
      : query.eq(Tb.images.unit, unit!));
    return response.isNotEmpty;
  }


}
