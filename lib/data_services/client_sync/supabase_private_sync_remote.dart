import 'package:festapp_core/sync.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class SupabasePrivateSyncRemote implements PrivateSyncRemote {
  SupabasePrivateSyncRemote(this._client);
  final SupabaseClient _client;

  @override
  Future<PrivateSyncResponse> getChanges(
      SyncContext context, Map<ClientSyncComponent, int> knownVector) async {
    final raw = await _client.rpc('get_private_client_sync_v1', params: {
      'p_context': {
        'organizationId': context.organizationId,
        'occasionId': context.occasionId,
      },
      'p_known_private_vector':
          knownVector.map((key, value) => MapEntry(key.wireName, value)),
    });
    final json = (raw as Map).cast<String, dynamic>();
    if (json['code'] != 200) {
      throw StateError('Private sync rejected with code ${json['code']}');
    }
    final data = (json['data'] as Map).cast<String, dynamic>();
    final vector =
        ((data['vector'] as Map?) ?? const {}).cast<String, dynamic>();
    final replacements =
        ((data['components'] as List?) ?? const []).map((item) {
      final component = (item as Map).cast<String, dynamic>();
      final parsed =
          ClientSyncComponentWireName.parse(component['component'] as String);
      if (!parsed.isPrivate) {
        throw const FormatException(
            'Private handshake returned a public component');
      }
      return PrivateComponentReplacement(
        component: parsed,
        revision: component['revision'] as int,
        payload: component['payload'],
      );
    }).toList(growable: false);
    return PrivateSyncResponse(
      serverTime: DateTime.parse(data['serverTime'] as String).toUtc(),
      vector: vector.map((key, value) {
        final component = ClientSyncComponentWireName.parse(key);
        if (!component.isPrivate) {
          throw const FormatException(
              'Private vector contains a public component');
        }
        return MapEntry(component, value as int);
      }),
      replacements: replacements,
    );
  }
}
