import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:fstapp/app_config.dart';

/// Both the UI and MCP resume the same SQL manifest in the canonical Worker.
Future<void> completeOccasionMedia(
  SupabaseClient client,
  String commandId,
) async {
  final token = client.auth.currentSession?.accessToken;
  if (token == null) throw StateError('Authentication required');
  final response = await http
      .post(
        Uri.parse('${AppConfig.imageApiUrl}/occasion-lifecycle'),
        headers: {
          'Authorization': 'Bearer $token',
          'Content-Type': 'application/json',
        },
        body: jsonEncode({
          'projectId': AppConfig.imageProjectId,
          'commandId': commandId,
        }),
      )
      .timeout(const Duration(seconds: 45));
  if (response.statusCode != 200) throw StateError('OCCASION_MEDIA_PENDING');
  final result = jsonDecode(response.body) as Map;
  if (result['commandId'] != commandId || result['state'] != 'complete') {
    throw StateError('OCCASION_MEDIA_PENDING');
  }
}
