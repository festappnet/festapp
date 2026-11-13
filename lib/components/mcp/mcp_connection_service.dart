import 'package:supabase_flutter/supabase_flutter.dart';

/// The first-party API keeps both refresh credentials and broker secrets off
/// the browser. The SDK supplies the current app access proof in its header.
class McpConnectionService {
  static Future<Map<String, dynamic>> request(
    String request,
    String operation,
    Map<String, dynamic> access, {
    Map<String, String>? mfa,
  }) async {
    final response = await Supabase.instance.client.functions.invoke(
      'mcp-session-exchange',
      headers: {
        if (Uri.base.queryParameters['issuer'] case final String issuer)
          'X-Festapp-Mcp-Issuer': issuer,
      },
      body: {
        'request': request,
        'operation': operation,
        'access': access,
        'mfa': ?mfa,
      },
    );
    return Map<String, dynamic>.from(response.data as Map);
  }

  static Uri resumeUri(Object? value) {
    final uri = Uri.tryParse(value?.toString() ?? '');
    if (uri == null ||
        uri.scheme != 'https' ||
        !const {
          'https://mcp.festapp.net',
          'https://mcp.vstupenky.online',
        }.contains(uri.origin) ||
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
