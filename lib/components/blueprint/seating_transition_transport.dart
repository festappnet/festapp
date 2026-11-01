import 'package:festapp_core/sync.dart';
import 'package:fstapp/data_services/client_sync/client_command_transport.dart';
import 'package:fstapp/data_services/client_sync/client_command_replacements.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'seating_transition_models.dart';

class SeatingTransitionTransport {
  SeatingTransitionTransport(SupabaseClient client)
    : this.withTransport(
        (name, params) => client.rpc(name, params: params),
        ClientCommandTransport.supabase(
          client,
          durable: true,
          retrySerialization: true,
        ),
      );
  SeatingTransitionTransport.withTransport(this._rpc, this._commands);
  final ClientCommandRpc _rpc;
  final ClientCommandTransport _commands;
  String? get principalBinding => _commands.principalBinding;
  static const operations = [
    'start_seating_configuration',
    'set_ticket_seat_assignments',
    'publish_seating_transitions',
    'cancel_seating_configuration',
  ];

  Future<Map<String, dynamic>> _read(
    String name,
    Map<String, dynamic> params,
  ) async {
    Object? raw;
    try {
      raw = await _rpc(name, params);
    } on PostgrestException catch (error) {
      if (error.code == '42501') throw const SeatingRejection('FORBIDDEN');
      rethrow;
    }
    final result = seatingMap(raw);
    final data = seatingMap(result['data']);
    if (result['code'] != 200)
      throw SeatingRejection(
        data['reason'] as String? ?? 'UNAVAILABLE',
        seatingRows(data['blockers']),
      );
    return data;
  }

  Future<Map<String, dynamic>> workspace(int occasion, int? blueprint) => _read(
    'get_seating_workspace',
    {'p_occasion': occasion, 'p_blueprint': blueprint},
  );
  Future<SeatingContext> context(
    String id, {
    String search = '',
    String? category,
    int? after,
  }) async => SeatingContext(
    await _read('get_seating_transition_context', {
      'p_transition': id,
      'p_search': search,
      'p_category': category,
      'p_after': after,
      'p_limit': 50,
    }),
  );
  Future<SeatingPreview> previewAssignments(
    String id,
    List<SeatingMapping> mappings,
  ) async => SeatingPreview(
    await _read('preview_ticket_seat_assignment', {
      'p_transition': id,
      'p_mappings': mappings.map((m) => m.toJson()).toList(),
    }),
  );
  Future<SeatingPreview> previewPublication(String id) async => SeatingPreview(
    await _read('preview_seating_publication', {'p_transition': id}),
  );

  Future<Map<String, dynamic>> mutate(
    String operation,
    Map<String, dynamic> parameters,
  ) async {
    if (!operations.contains(operation)) throw ArgumentError.value(operation);
    final response = ClientCommandResponse.from(
      await _commands.invokeIntent('seating', operation, parameters),
    );
    return _accept(response);
  }

  Future<Map<String, dynamic>> _accept(ClientCommandResponse response) async {
    if (response.code == 410)
      throw const FormatException('Unresolved expired receipt');
    if (response.code != 200)
      throw SeatingRejection(
        response.data['reason'] as String? ?? 'UNAVAILABLE',
        seatingRows(response.data['blockers']),
      );
    await response.applyConfirmedReplacements();
    return response.data;
  }

  Future<bool> recoverStart(int formId, int blueprintId) async {
    if (_commands.principalBinding == null) return false;
    final intent = await _commands.pendingIntent(
      'start_seating_configuration',
      {'p_form': formId, 'p_blueprint': blueprintId},
    );
    if (intent == null) return false;
    await _accept(ClientCommandResponse.from(await _commands.resume(intent)));
    return true;
  }

  // Recover the persisted exact bytes before allowing a new reviewed command.
  Future<bool> recover(String id) async {
    if (_commands.principalBinding == null) return false;
    var recovered = false;
    for (final operation in operations.skip(1)) {
      final intent = await _commands.pendingIntent(operation, {
        'p_transition': id,
      });
      if (intent != null) {
        await _accept(
          ClientCommandResponse.from(await _commands.resume(intent)),
        );
        recovered = true;
      }
    }
    return recovered;
  }
}
