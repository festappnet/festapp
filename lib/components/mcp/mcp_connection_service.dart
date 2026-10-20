import 'package:supabase_flutter/supabase_flutter.dart';

/// The first-party API keeps both refresh credentials and broker secrets off
/// the browser. The SDK supplies the current app access proof in its header.
class McpConnectionService {
  static Future<Map<String, dynamic>> request(
      String request, String operation, List<int> occasions) async {
    final response = await Supabase.instance.client.functions.invoke(
      'mcp-session-exchange',
      body: {
        'request': request,
        'operation': operation,
        'occasions': occasions
      },
    );
    return Map<String, dynamic>.from(response.data as Map);
  }

  static Uri resumeUri(Object? value) {
    final uri = Uri.tryParse(value?.toString() ?? '');
    if (uri == null ||
        uri.scheme != 'https' ||
        uri.origin != 'https://mcp.festapp.net' ||
        uri.userInfo.isNotEmpty ||
        uri.fragment.isNotEmpty ||
        !RegExp(r'^/connect/[A-Za-z0-9_-]+/finish$').hasMatch(uri.path) ||
        !RegExp(r'^[A-Za-z0-9_-]{43}$')
            .hasMatch(uri.queryParameters['resume'] ?? '') ||
        uri.queryParameters.length != 1) {
      throw const FormatException('Invalid connection continuation');
    }
    return uri;
  }
}
