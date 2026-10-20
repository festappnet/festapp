import 'package:fstapp/data_services/client_sync/client_command_replacements.dart';
import 'package:festapp_core/sync.dart';
import 'package:fstapp/data_services/client_sync/client_command_transport.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class CleaningCommandResult {
  const CleaningCommandResult({
    required this.status,
    required this.code,
    required this.data,
  });

  final String status;
  final int code;
  final Map<String, dynamic> data;
}

abstract interface class CleaningCommands {
  Future<CleaningCommandResult> report({
    required int placeId,
    required String problemType,
    String? note,
  });
  Future<CleaningCommandResult> resolve(int placeId);
  Future<CleaningCommandResult> setNotificationsMuted(
    int occasionId,
    bool muted,
  );
  Future<CleaningCommandResult> setReporterBlocked(
    int occasionId,
    String userId,
    bool blocked,
  );
}

class SupabaseCleaningCommands implements CleaningCommands {
  SupabaseCleaningCommands(SupabaseClient client)
      : _transport = ClientCommandTransport.supabase(client, durable: true);

  SupabaseCleaningCommands.withTransport(this._transport);

  final ClientCommandTransport _transport;

  @override
  Future<CleaningCommandResult> report({
    required int placeId,
    required String problemType,
    String? note,
  }) =>
      _invoke('report_cleaning_issue_client_sync_v1', {
        'p_place': placeId,
        'p_problem_type': problemType,
        'p_note': note,
      });

  @override
  Future<CleaningCommandResult> resolve(int placeId) =>
      _invoke('resolve_cleaning_place_client_sync_v1', {'p_place': placeId});

  @override
  Future<CleaningCommandResult> setNotificationsMuted(
    int occasionId,
    bool muted,
  ) =>
      _invoke('set_cleaning_notifications_muted_client_sync_v1', {
        'p_occasion': occasionId,
        'p_muted': muted,
      });

  @override
  Future<CleaningCommandResult> setReporterBlocked(
    int occasionId,
    String userId,
    bool blocked,
  ) =>
      _invoke('set_cleaning_reporter_blocked_client_sync_v1', {
        'p_occasion': occasionId,
        'p_user': userId,
        'p_blocked': blocked,
      });

  Future<CleaningCommandResult> _invoke(
    String name,
    Map<String, dynamic> parameters,
  ) async {
    final response = ClientCommandResponse.from(
      await _transport.invoke(name, parameters),
    );
    await applyClientCommandReplacements(response);
    return CleaningCommandResult(
      status: response.status,
      code: response.code,
      data: response.data,
    );
  }
}
