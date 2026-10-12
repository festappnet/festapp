import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class SupabaseStorageService {
  static const String _bucketName = 'editor-files';

  static final _supabase = Supabase.instance.client;

  static Future<bool> uploadFile(
      BuildContext context, Uint8List data, String format) async {
    final path = '${DateTime.now().millisecondsSinceEpoch}.$format';
    final uploadResponse =
        await _supabase.storage.from(_bucketName).uploadBinary(path, data);
    if (uploadResponse.isEmpty) {}
    return false;
  }
}
