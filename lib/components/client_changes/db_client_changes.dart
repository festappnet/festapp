import 'package:fstapp/components/client_changes/client_change_model.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class DbClientChanges {
  DbClientChanges([SupabaseClient? client])
      : _client = client ?? Supabase.instance.client;
  final SupabaseClient _client;

  Future<List<ClientActivityDay>> activity({
    required int occasionId,
    required DateTime from,
    required DateTime to,
  }) async {
    final raw = await _client.rpc('get_client_activity_v1', params: {
      'p_occasion': occasionId,
      'p_from': from.toUtc().toIso8601String(),
      'p_to': to.toUtc().toIso8601String(),
    });
    final json = (raw as Map).cast<String, dynamic>();
    if (json['code'] != 200) {
      throw StateError('Client activity returned ${json['code']}');
    }
    return ((json['data'] as List?) ?? const [])
        .map((item) =>
            ClientActivityDay.fromJson((item as Map).cast<String, dynamic>()))
        .toList(growable: false);
  }
}
