import 'dart:convert';
import 'dart:typed_data';

import 'package:http/http.dart' as http;
import 'package:http_parser/http_parser.dart';

import 'image_file_format.dart';
import 'image_upload_profile.dart';
import 'image_upload_limits.dart';
export 'image_upload_profile.dart';

class ImageUploadResult {
  const ImageUploadResult(this.url, {this.asset});
  final String url;
  final Map<String, dynamic>? asset;
}

class ImageControlClient {
  final String endpoint;
  final String projectId;
  final http.Client httpClient;

  const ImageControlClient({
    required this.endpoint,
    required this.projectId,
    required this.httpClient,
  });

  Future<String> upload({
    required Uint8List bytes,
    required String filename,
    required String accessToken,
    int? occasionId,
    int? unitId,
    ImageUploadProfile profile = ImageUploadProfile.standard,
  }) async => (await uploadWithResult(bytes: bytes, filename: filename,
      accessToken: accessToken, occasionId: occasionId, unitId: unitId,
      profile: profile)).url;


  Future<ImageUploadResult> uploadWithResult({
    required Uint8List bytes,
    required String filename,
    required String accessToken,
    int? occasionId,
    int? unitId,
    ImageUploadProfile profile = ImageUploadProfile.standard,
  }) async {
    if (bytes.length > ImageUploadLimits.maxInputBytes)
      throw const FormatException('Image exceeds 20 MB');
    final format = ImageFileFormat.detect(bytes, allowSvg: profile == ImageUploadProfile.blueprintBackground);
    final stem = filename.replaceFirst(RegExp(r'\.[^.]*$'), '');
    final request = http.MultipartRequest('POST', Uri.parse('$endpoint/upload'))
      ..headers['Authorization'] = 'Bearer $accessToken'
      ..fields['projectId'] = projectId
      ..fields['profile'] = profile.wireName
      ..files.add(
        http.MultipartFile.fromBytes(
          'file',
          bytes,
          filename: '$stem.${format.extension}',
          contentType: MediaType.parse(format.mime),
        ),
      );
    if (occasionId != null) request.fields['occasionId'] = '$occasionId';
    if (unitId != null) request.fields['unitId'] = '$unitId';

    late http.StreamedResponse streamed;
    late String responseBody;
    try {
      streamed = await httpClient
          .send(request)
          .timeout(const Duration(seconds: 45));
      responseBody = await streamed.stream.bytesToString().timeout(
        const Duration(seconds: 45),
      );
    } catch (error) {
      throw ImageUploadOutcomeUnknown(error);
    }
    if (streamed.statusCode >= 500)
      throw ImageUploadOutcomeUnknown(streamed.statusCode);
    if (streamed.statusCode != 200)
      throw ImageUploadRejected(streamed.statusCode);
    try {
      final payload = jsonDecode(responseBody) as Map<String, dynamic>;
      final url = payload['url'] as String;
      final uri = Uri.parse(url);
      if (uri.scheme != 'https' || uri.host.isEmpty || uri.userInfo.isNotEmpty)
        throw const FormatException('Invalid permanent image URL');
      Map<String, dynamic>? asset;
      if (profile == ImageUploadProfile.blueprintBackground) {
        final raw = payload['asset'];
        if (raw is! Map || raw['state'] != 'ready' || raw['url'] != url ||
            raw['hash'] is! String || !RegExp(r'^[a-f0-9]{64}$').hasMatch(raw['hash']) ||
            raw['assetRef'] != 'image:${raw['hash']}' ||
            raw['width'] is! int || raw['width'] <= 0 ||
            raw['height'] is! int || raw['height'] <= 0 ||
            raw['byteLength'] is! int || raw['byteLength'] <= 0 ||
            !const ['image/png', 'image/jpeg', 'image/webp'].contains(raw['mimeType'])) {
          throw const FormatException('Invalid processed background manifest');
        }
        asset = Map<String, dynamic>.unmodifiable(Map<String, dynamic>.from(raw));
      }
      return ImageUploadResult(url, asset: asset);
    } catch (error) {
      throw ImageUploadOutcomeUnknown(error);
    }
  }

  Future<void> deleteLinks(List<String> links, String accessToken) async {
    final response = await httpClient.post(
      Uri.parse('$endpoint/delete'),
      headers: {
        'Authorization': 'Bearer $accessToken',
        'Content-Type': 'application/json',
      },
      body: jsonEncode({'projectId': projectId, 'links': links}),
    );
    if (response.statusCode != 200)
      throw Exception('Image delete incomplete: ${response.body}');
  }

  Future<Uint8List> download(String url, {String? accessToken}) async {
    final uri = Uri.parse(url);
    if (uri.scheme != 'https' || uri.host.isEmpty || uri.userInfo.isNotEmpty) {
      throw const FormatException('Invalid image URL');
    }
    // Client memory bound matches the upload protocol's 20 MB input envelope.
    // The Worker independently enforces actual bytes and central SQL budgets.
    const maxInputBytes = ImageUploadLimits.maxInputBytes;
    final request = http.Request('GET', uri);
    if (uri.path.startsWith('/private/')) {
      final control = Uri.parse(endpoint);
      if (uri.host != control.host ||
          uri.scheme != control.scheme || uri.port != control.port ||
          accessToken == null) {
        throw const FormatException('Private image authorization required');
      }
      request.followRedirects = false;
      request.headers['Authorization'] = 'Bearer $accessToken';
    }
    final response =
        await httpClient.send(request).timeout(const Duration(seconds: 30));
    if (response.statusCode != 200) {
      throw ImageDownloadException(response.statusCode);
    }
    final bytes = BytesBuilder(copy: false);
    await for (final chunk in response.stream.timeout(
      const Duration(seconds: 30),
    )) {
      if (bytes.length + chunk.length > maxInputBytes) {
        throw const FormatException('Image exceeds the upload input limit');
      }
      bytes.add(chunk);
    }
    return bytes.takeBytes();
  }
}

class ImageUploadOutcomeUnknown implements Exception {
  const ImageUploadOutcomeUnknown(this.cause);
  final Object cause;
  @override
  String toString() =>
      'Image upload outcome is unknown; retry can create another asset.';
}

class ImageUploadRejected implements Exception {
  const ImageUploadRejected(this.status);
  final int status;
  @override
  String toString() => 'Image upload rejected ($status)';
}

class ImageDownloadException implements Exception {
  final int status;
  const ImageDownloadException(this.status);
}
