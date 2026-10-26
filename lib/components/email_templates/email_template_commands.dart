import 'package:festapp_core/sync.dart';
import 'package:fstapp/data_services/client_sync/client_command_replacements.dart';
import 'package:fstapp/data_services/client_sync/client_command_transport.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Same durable compare-and-set command used by the MCP adapter.
class EmailTemplateCommands {
  EmailTemplateCommands(SupabaseClient client)
    : this.withTransport(
        ClientCommandTransport.supabase(client, durable: true),
      );
  EmailTemplateCommands.withTransport(this._transport);
  final ClientCommandTransport _transport;

  Future<Map<String, dynamic>> change({
    required String entityType,
    required int entityId,
    required int organizationId,
    required int unitId,
    required String code,
    required String expectedRevision,
    required String action,
    Map<String, dynamic> payload = const {},
  }) async {
    final response = ClientCommandResponse.from(
      await _transport.invoke('manage_email_template', {
        'p_entity_type': entityType,
        'p_entity_id': entityId,
        'p_organization': organizationId,
        'p_unit': unitId,
        'p_action': action,
        'p_code': code,
        'p_expected_revision': expectedRevision,
        'p_payload': payload,
      }),
    );
    if (response.code == 409) {
      throw StateError('EMAIL_TEMPLATE_CHANGED_RELOAD_REQUIRED');
    }
    if (response.code != 200) {
      throw StateError('Email template command rejected');
    }
    await applyClientCommandReplacements(response);
    return Map<String, dynamic>.from(
      (response.data['templates'] as List).single,
    );
  }

  Future<Map<String, dynamic>> banner({
    required String entityType,
    required int entityId,
    required int organizationId,
    required int unitId,
    required String expectedRevision,
    String? bannerUrl,
  }) async {
    final response = ClientCommandResponse.from(
      await _transport.invoke('manage_email_banner', {
        'p_entity_type': entityType,
        'p_entity_id': entityId,
        'p_organization': organizationId,
        'p_unit': unitId,
        'p_expected_revision': expectedRevision,
        'p_banner_url': bannerUrl,
      }),
    );
    if (response.code == 409) {
      throw StateError('EMAIL_BANNER_CHANGED_RELOAD_REQUIRED');
    }
    if (response.code != 200) {
      throw StateError('Email banner command rejected');
    }
    await applyClientCommandReplacements(response);
    return response.data;
  }
}
