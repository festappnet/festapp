import 'package:fstapp/components/occasion/occasion_model.dart';
import 'package:fstapp/data_services/client_sync/client_command_response.dart';
import 'package:fstapp/data_services/client_sync/client_command_transport.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

abstract interface class OccasionCommands {
  Future<OccasionModel> create(OccasionModel occasion);
  Future<OccasionModel> save(OccasionModel occasion);
  Future<int> duplicate(int occasionId);
  Future<void> delete(int occasionId);
  Future<Map<String, dynamic>> deleteService(
    int occasionId,
    String type,
    String code,
    bool force,
  );
  Future<Map<String, dynamic>> createService(
    int occasionId,
    String type,
    String code,
    String title,
    int? reference,
  );
  Future<Map<String, dynamic>> updateService(
    int occasionId,
    String type,
    String code,
    String title,
    int? reference,
  );
  Future<Map<String, dynamic>> updateGameSettings(
    int occasionId,
    DateTime? start,
    DateTime? end,
  );
}

class SupabaseOccasionCommands implements OccasionCommands {
  SupabaseOccasionCommands(SupabaseClient client)
      : _transport = ClientCommandTransport.supabase(client);

  SupabaseOccasionCommands.withTransport(this._transport);

  final ClientCommandTransport _transport;

  @override
  Future<OccasionModel> create(OccasionModel occasion) async {
    if (occasion.id != null) {
      throw ArgumentError('The create command requires an unsaved occasion');
    }
    final response = ClientCommandResponse.from(
      await _transport.invoke('create_occasion_client_sync_v1', {
        'p_config': occasion.toSaveJson(),
      }),
    );
    if (response.code != 200 || response.data['occasion'] is! Map) {
      throw StateError('Occasion creation was rejected');
    }
    return OccasionModel.fromJson(
      (response.data['occasion'] as Map).cast<String, dynamic>(),
    );
  }

  @override
  Future<OccasionModel> save(OccasionModel occasion) async {
    final id = occasion.id;
    if (id == null) {
      throw ArgumentError(
          'The v1 occasion command updates an existing occasion');
    }
    final response = ClientCommandResponse.from(
      await _transport.invoke('save_occasion_client_sync_v1', {
        'p_occasion': id,
        'p_expected_version': occasion.aggregateVersion,
        'p_config': occasion.toSaveJson(),
      }),
    );
    if (response.status == 'conflict') {
      throw StateError('Occasion was changed by another editor');
    }
    if (response.status == 'rejected') {
      throw StateError('Occasion save was rejected');
    }
    await response.applyReplacements();
    return OccasionModel.fromJson(
      (response.data['occasion'] as Map).cast<String, dynamic>(),
    );
  }

  @override
  Future<int> duplicate(int occasionId) async {
    final response = ClientCommandResponse.from(await _transport.invoke(
      'duplicate_occasion_client_sync_v1',
      {'p_occasion': occasionId},
    ));
    if (response.code != 200 || response.data['occasionId'] is! num) {
      throw StateError('Occasion duplication was rejected');
    }
    return (response.data['occasionId'] as num).toInt();
  }

  @override
  Future<void> delete(int occasionId) async {
    final response = ClientCommandResponse.from(await _transport.invoke(
      'delete_occasion_client_sync_v1',
      {'p_occasion': occasionId},
    ));
    if (response.code != 200) {
      throw StateError('Occasion deletion was rejected');
    }
  }

  @override
  Future<Map<String, dynamic>> deleteService(
    int occasionId,
    String type,
    String code,
    bool force,
  ) async {
    final response = ClientCommandResponse.from(await _transport.invoke(
      'delete_service_item_client_sync_v1',
      {
        'p_occasion': occasionId,
        'p_type': type,
        'p_code': code,
        'p_force': force,
      },
    ));
    await response.applyReplacements();
    return {'code': response.code, ...response.data};
  }

  @override
  Future<Map<String, dynamic>> createService(
    int occasionId,
    String type,
    String code,
    String title,
    int? reference,
  ) =>
      _configurationCommand('create_service_item_client_sync_v1', {
        'p_occasion': occasionId,
        'p_type': type,
        'p_code': code,
        'p_title': title,
        'p_reference': reference,
      });

  @override
  Future<Map<String, dynamic>> updateService(
    int occasionId,
    String type,
    String code,
    String title,
    int? reference,
  ) =>
      _configurationCommand('update_service_item_client_sync_v1', {
        'p_occasion': occasionId,
        'p_type': type,
        'p_code': code,
        'p_title': title,
        'p_reference': reference,
      });

  @override
  Future<Map<String, dynamic>> updateGameSettings(
    int occasionId,
    DateTime? start,
    DateTime? end,
  ) =>
      _configurationCommand('game_update_settings_client_sync_v1', {
        'p_occasion': occasionId,
        'p_start': start?.toIso8601String(),
        'p_end': end?.toIso8601String(),
      });

  Future<Map<String, dynamic>> _configurationCommand(
    String functionName,
    Map<String, dynamic> parameters,
  ) async {
    final response = ClientCommandResponse.from(
      await _transport.invoke(functionName, parameters),
    );
    await response.applyReplacements();
    return {'code': response.code, ...response.data};
  }
}
