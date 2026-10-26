import 'package:fstapp/components/unit/unit_model.dart';
import 'package:fstapp/data_services/rights_service.dart';
import 'package:festapp_core/sync.dart';
import 'package:fstapp/data_services/client_sync/client_command_transport.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

abstract interface class UnitCommands {
  Future<UnitModel> save(UnitModel unit);
  Future<void> deleteUserAccess(int unitId, String userId);
}

class SupabaseUnitCommands implements UnitCommands {
  SupabaseUnitCommands(SupabaseClient client)
    : _transport = ClientCommandTransport.supabase(client);

  SupabaseUnitCommands.withTransport(this._transport);

  final ClientCommandTransport _transport;

  @override
  Future<void> deleteUserAccess(int unitId, String userId) async {
    final response = ClientCommandResponse.from(
      await _transport.invoke('delete_unit_user_client_sync_v1', {
        'p_unit': unitId,
        'p_user': userId,
      }),
    );
    if (response.code != 200) {
      throw StateError('Unit user deletion was rejected');
    }
    if (userId == RightsService.currentUser()?.id) {
      await RightsService.refreshAfterAuthorizationChange();
    }
  }

  @override
  Future<UnitModel> save(UnitModel unit) async {
    final id = unit.id;
    if (id == null) throw ArgumentError('Unit save requires its ID');
    final response = ClientCommandResponse.from(
      await _transport.invoke('save_unit_client_sync_v1', {
        'p_unit': id,
        'p_expected_version': unit.aggregateVersion,
        'p_unit_data': {
          'id': id,
          'title': unit.title,
          'settings': {
            for (final key in ['reply_to', 'communication_tone', 'timezone'])
              key: unit.data?[key],
          },
        },
      }),
    );
    if (response.status == 'conflict') {
      throw StateError('Unit was changed by another manager');
    }
    final raw = response.data['unit'];
    if (response.code != 200 || raw is! Map) {
      throw StateError('Unit save was rejected');
    }
    return UnitModel.fromJson(raw.cast<String, dynamic>());
  }
}
