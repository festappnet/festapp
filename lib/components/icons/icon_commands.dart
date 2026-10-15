import 'package:fstapp/data_services/client_sync/client_command_replacements.dart';
import 'package:fstapp/components/map/icon_model.dart';
import 'package:fstapp/data_services/client_sync/client_command_transport.dart';
import 'package:festapp_core/sync.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

enum IconCommandStatus { applied, unchanged, rejected, conflict }

class IconCommandResult {
  const IconCommandResult({required this.status, this.icon, this.refs});

  final IconCommandStatus status;
  final IconModel? icon;
  final Map<String, dynamic>? refs;
}

abstract interface class IconCommands {
  Future<IconCommandResult> create(
      {required int occasionId, required String link, required String svg});
  Future<IconCommandResult> delete(
      {required int occasionId, required int iconId});
}

class SupabaseIconCommands implements IconCommands {
  SupabaseIconCommands(SupabaseClient client)
      : _transport = ClientCommandTransport.supabase(client);

  SupabaseIconCommands.withTransport(this._transport);

  final ClientCommandTransport _transport;

  @override
  Future<IconCommandResult> create({
    required int occasionId,
    required String link,
    required String svg,
  }) async =>
      _decode(await _transport.invoke('save_icon_client_sync_v1', {
        'p_occasion': occasionId,
        'p_icon': {'link': link, 'svg': svg},
      }));

  @override
  Future<IconCommandResult> delete({
    required int occasionId,
    required int iconId,
  }) async =>
      _decode(await _transport.invoke('delete_icon_client_sync_v1', {
        'p_occasion': occasionId,
        'p_icon_id': iconId,
      }));

  Future<IconCommandResult> _decode(Object? raw) async {
    final response = ClientCommandResponse.from(raw);
    await applyClientCommandReplacements(response);
    final data = response.data;
    final icon = data['icon'];
    return IconCommandResult(
      status: IconCommandStatus.values.byName(response.status),
      icon:
          icon is Map ? IconModel.fromJson(icon.cast<String, dynamic>()) : null,
      refs: (data['refs'] as Map?)?.cast<String, dynamic>(),
    );
  }
}
