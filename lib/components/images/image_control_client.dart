import 'dart:convert';
import 'dart:typed_data';

import 'package:http/http.dart' as http;
import 'package:http_parser/http_parser.dart';

import 'image_file_format.dart';
import 'image_upload_profile.dart';
import 'image_upload_limits.dart';
export 'image_upload_profile.dart';

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
  }) async {
    if (bytes.length > ImageUploadLimits.maxInputBytes)
      throw const FormatException('Image exceeds 20 MB');
    final format = ImageFileFormat.detect(bytes);
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
      streamed =
          await httpClient.send(request).timeout(const Duration(seconds: 45));
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
      final url =
          (jsonDecode(responseBody) as Map<String, dynamic>)['url'] as String;
      final uri = Uri.parse(url);
      if (uri.scheme != 'https' || uri.host.isEmpty || uri.userInfo.isNotEmpty)
        throw const FormatException('Invalid permanent image URL');
      return url;
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

  Future<Uint8List> download(String url) async {
    final uri = Uri.parse(url);
    if (uri.scheme != 'https' || uri.host.isEmpty || uri.userInfo.isNotEmpty) {
      throw const FormatException('Invalid image URL');
    }
    // Client memory bound matches the upload protocol's 20 MB input envelope.
    // The Worker independently enforces actual bytes and central SQL budgets.
    const maxInputBytes = ImageUploadLimits.maxInputBytes;
    final response = await httpClient
        .send(http.Request('GET', uri))
        .timeout(const Duration(seconds: 30));
    if (response.statusCode != 200) {
      throw Exception('Image download failed: ${response.statusCode}');
    }
    final bytes = BytesBuilder(copy: false);
    await for (final chunk
        in response.stream.timeout(const Duration(seconds: 30))) {
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
