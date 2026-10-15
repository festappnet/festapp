import 'package:fstapp/data_services/client_sync/client_command_replacements.dart';
import 'package:festapp_core/sync.dart';
import 'package:fstapp/data_services/client_sync/client_command_transport.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:fstapp/components/forms/form_commands.dart';

class SupabaseFormCommands implements FormCommands {
  SupabaseFormCommands(SupabaseClient client)
      : _transport = ClientCommandTransport.supabase(client);

  SupabaseFormCommands.withTransport(this._transport);

  final ClientCommandTransport _transport;

  @override
  Future<Map<String, dynamic>> create({
    required String occasionLink,
    required String link,
    required String title,
  }) =>
      _invoke('create_form_client_sync_v1', {
        'p_occasion_link': occasionLink,
        'p_link': link,
        'p_title': title,
      });

  @override
  Future<int> duplicate({
    required int sourceFormId,
    required String targetOccasionLink,
  }) async {
    final data = await _invoke('duplicate_form_to_occasion_client_sync_v1', {
      'p_source_form_id': sourceFormId,
      'p_target_occasion_link': targetOccasionLink,
    });
    final id = data['formId'];
    if (id is! num) throw StateError('Form duplication returned no form ID');
    return id.toInt();
  }

  @override
  Future<void> delete(int formId) async {
    await _invoke('delete_form_client_sync_v1', {'p_form_id': formId});
  }

  @override
  Future<Map<String, dynamic>> save(Map<String, dynamic> form) =>
      _invoke('update_form_client_sync_v1', {'p_form': form});

  @override
  Future<Map<String, dynamic>> saveBlueprint(
    Map<String, dynamic> blueprint,
  ) =>
      _invoke(
        'update_blueprint_client_sync_v1',
        {'p_blueprint': blueprint},
      );

  Future<Map<String, dynamic>> _invoke(
    String functionName,
    Map<String, dynamic> parameters,
  ) async {
    final response = ClientCommandResponse.from(
      await _transport.invoke(functionName, parameters),
    );
    if (response.code != 200) {
      throw StateError(response.data['message']?.toString() ?? 'Form rejected');
    }
    await applyClientCommandReplacements(response);
    return response.data;
  }
}
