import 'package:fstapp/components/blueprint/blueprint_command_rejection.dart';
import 'package:fstapp/data_services/client_sync/client_command_replacements.dart';
import 'package:festapp_core/sync.dart';
import 'package:fstapp/data_services/client_sync/client_command_transport.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class TicketCancellationOutcome {
  const TicketCancellationOutcome({
    this.cancelledOrderIds = const [],
    this.updatedOrders = const [],
  });

  final List<int> cancelledOrderIds;
  final List<({int id, String email})> updatedOrders;

  factory TicketCancellationOutcome.fromJson(Map<String, dynamic> data) =>
      TicketCancellationOutcome(
        cancelledOrderIds: (data['cancelledOrderIds'] as List? ?? const [])
            .map((id) => (id as num).toInt())
            .toList(),
        updatedOrders: (data['updatedOrders'] as List? ?? const [])
            .map(
              (raw) => (
                id: (raw['id'] as num).toInt(),
                email: raw['email'] as String? ?? '',
              ),
            )
            .toList(),
      );
}

abstract interface class TicketCommands {
  Future<void> swapSpots(int firstSpotId, int secondSpotId);
  Future<TicketCancellationOutcome> cancel(List<int> ticketIds);
}

class SupabaseTicketCommands implements TicketCommands {
  SupabaseTicketCommands(SupabaseClient client)
      : _transport = ClientCommandTransport.supabase(client);

  SupabaseTicketCommands.withTransport(this._transport);

  final ClientCommandTransport _transport;

  @override
  Future<TicketCancellationOutcome> cancel(List<int> ticketIds) async {
    final response = ClientCommandResponse.from(
      await _transport.invoke('storno_tickets_client_sync_v1', {
        'p_tickets': ticketIds,
      }),
    );
    if (response.code != 200) {
      throw BlueprintCommandRejection(response.code, response.data);
    }
    await applyClientCommandReplacements(response);
    return TicketCancellationOutcome.fromJson(response.data);
  }

  @override
  Future<void> swapSpots(int firstSpotId, int secondSpotId) async {
    final response = ClientCommandResponse.from(
      await _transport.invoke('swap_spot_tickets_client_sync_v1', {
        'p_spot_1': firstSpotId,
        'p_spot_2': secondSpotId,
      }),
    );
    if (response.code != 200) {
      throw BlueprintCommandRejection(response.code, response.data);
    }
    await applyClientCommandReplacements(response);
  }
}
