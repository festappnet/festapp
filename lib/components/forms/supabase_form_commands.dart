import 'dart:convert';

import 'package:fstapp/data_services/client_sync/client_command_replacements.dart';
import 'package:festapp_core/sync.dart';
import 'package:fstapp/data_services/client_sync/client_command_transport.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:fstapp/components/forms/form_commands.dart';
import 'package:fstapp/components/blueprint/blueprint_command_rejection.dart';

class SupabaseFormCommands implements FormCommands {
  SupabaseFormCommands(SupabaseClient client)
    : _transport = ClientCommandTransport.supabase(client, durable: true);

  SupabaseFormCommands.withTransport(this._transport);
  final ClientCommandTransport _transport;
  final Map<String, ClientCommandResponse> _blueprintReceipts = {};

  @override
  Future<Map<String, dynamic>> create({
    required String occasionLink,
    required String link,
    required String title,
  }) => _invoke('create_form_client_sync_v1', {
    'p_occasion_link': occasionLink,
    'p_link': link,
    'p_title': title,
  });

  @override
  Future<int> duplicate({
    required int sourceFormId,
    required String targetOccasionLink,
    String locale = 'en',
  }) async {
    final data = await _invoke('duplicate_form_to_occasion_client_sync_v1', {
      'p_source_form_id': sourceFormId,
      'p_target_occasion_link': targetOccasionLink,
      'p_locale': locale,
    });
    final id = data['formId'];
    if (id is! num) throw StateError('Form duplication returned no form ID');
    return id.toInt();
  }

  @override
  Future<void> delete(int formId, {required int expectedVersion}) async {
    await _invoke('delete_form_client_sync_v1', {
      'p_form_id': formId,
      'p_expected_version': expectedVersion,
    });
  }

  @override
  Future<Map<String, dynamic>> save(Map<String, dynamic> form) {
    if (form['expected_aggregate_version'] is! int ||
        form['expected_product_versions'] is! Map ||
        form['expected_product_type_versions'] is! Map) {
      throw StateError('Original form and product versions required');
    }
    return _invoke('update_form_client_sync_v1', {'p_form': form});
  }

  @override
  Future<Map<String, dynamic>> saveBlueprint(
    Map<String, dynamic> blueprint,
  ) async {
    if (blueprint['layout'] is! Map ||
        blueprint['expected_layout_revision'] is! int) {
      throw StateError('BLUEPRINT_LAYOUT_REQUIRED');
    }
    final parameters = {'p_blueprint': blueprint};
    final key = jsonEncode(blueprint);
    final response =
        _blueprintReceipts[key] ??
        ClientCommandResponse.from(
          await _transport.invokeIntent(
            'blueprint:${blueprint['id']}',
            'update_blueprint_client_sync_v1',
            parameters,
          ),
        );
    if (response.code != 200) {
      _blueprintReceipts.remove(key);
      throw BlueprintCommandRejection(response.code, response.data);
    }
    _blueprintReceipts[key] = response;
    if (response.data['layout_revision'] is! num ||
        response.data['seatBindings'] is! List) {
      throw const FormatException('Invalid blueprint save acknowledgement');
    }
    await applyClientCommandReplacements(response);
    _blueprintReceipts.remove(key);
    return response.data;
  }

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
