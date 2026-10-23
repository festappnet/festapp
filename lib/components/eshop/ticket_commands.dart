import 'dart:convert';
import 'package:fstapp/components/blueprint/blueprint_seat_swap_preview.dart';
import 'package:fstapp/components/blueprint/blueprint_hold_release_preview.dart';
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
  Future<BlueprintSeatSwapPreview> previewSwap(
      {required int occasionId,
      required int organizationId,
      int? unitId,
      required int blueprintId,
      required int firstSpotId,
      required int secondSpotId});
  Future<void> swapSpots(BlueprintSeatSwapPreview preview);
  Future<bool> recoverSwap(
      {required int occasionId,
      required int organizationId,
      int? unitId,
      required int blueprintId});
  Future<TicketCancellationOutcome> cancel(List<int> ticketIds);
  Future<BlueprintHoldReleasePreview> previewHoldRelease(List<int> spotIds,
      {required int occasionId, required int organizationId, int? unitId});
  Future<void> releaseHolds(BlueprintHoldReleasePreview preview);
}

class SupabaseTicketCommands implements TicketCommands {
  SupabaseTicketCommands(SupabaseClient client)
      : _transport = ClientCommandTransport.supabase(client, durable: true),
        _read = ((name, params) => client.rpc(name, params: params));

  SupabaseTicketCommands.withTransport(this._transport,
      {ClientCommandRpc? readRpc})
      : _read = readRpc;

  final ClientCommandTransport _transport;
  final ClientCommandRpc? _read;

  @override
  Future<TicketCancellationOutcome> cancel(List<int> ticketIds) async {
    final response = ClientCommandResponse.from(
      await _transport.invoke('storno_tickets_client_sync_v1', {
        'p_tickets': (ticketIds.toSet().toList()..sort()),
      }),
    );
    if (response.code != 200) {
      throw BlueprintCommandRejection(response.code, response.data);
    }
    await applyClientCommandReplacements(response);
    return TicketCancellationOutcome.fromJson(response.data);
  }

  @override
  Future<BlueprintHoldReleasePreview> previewHoldRelease(List<int> spotIds,
      {required int occasionId,
      required int organizationId,
      int? unitId}) async {
    final requested = List<int>.unmodifiable(spotIds);
    final raw = await _readRpc('preview_blueprint_hold_release', {
      'p_occasion': occasionId,
      'p_organization': organizationId,
      'p_unit': unitId,
      'p_spots': requested,
      'p_editor': true,
    });
    final preview = BlueprintHoldReleasePreview.fromJson(
        Map<String, dynamic>.from(raw as Map),
        organizationId: organizationId,
        unitId: unitId);
    if (preview.occasionId != occasionId)
      throw const FormatException('Reservation scope changed');
    return preview;
  }

  Future<Object?> _readRpc(String name, Map<String, dynamic> parameters) async {
    final read = _read;
    if (read == null) {
      throw StateError('Reservation preview transport required');
    }
    final principal = _transport.principalBinding;
    final result = await read(name, parameters);
    if (principal != _transport.principalBinding) {
      throw StateError('COMMAND_PRINCIPAL_CHANGED');
    }
    return result;
  }

  @override
  Future<void> releaseHolds(BlueprintHoldReleasePreview preview) async {
    final response = ClientCommandResponse.from(await _transport.invoke(
      'release_blueprint_holds',
      {
        'p_occasion': preview.occasionId,
        'p_organization': preview.organizationId,
        'p_unit': preview.unitId,
        'p_blueprint': preview.blueprintId,
        'p_spots': preview.requestedSpotIds,
        'p_affected_spots': preview.affectedSpotIds,
        'p_expected_revision': preview.layoutRevision,
        'p_hold_snapshot': preview.holdSnapshot,
        'p_editor': true
      },
    ));
    if (response.code != 200) {
      throw BlueprintCommandRejection(response.code, response.data);
    }
    // The DB receipt is authoritative; optional projection repair cannot turn
    // a completed release into an apparent domain failure.
    await response.applyConfirmedReplacements();
  }

  @override
  Future<BlueprintSeatSwapPreview> previewSwap(
      {required int occasionId,
      required int organizationId,
      int? unitId,
      required int blueprintId,
      required int firstSpotId,
      required int secondSpotId}) async {
    final raw = await _readRpc('preview_blueprint_seat_swap', {
      'p_occasion': occasionId,
      'p_organization': organizationId,
      'p_unit': unitId,
      'p_blueprint': blueprintId,
      'p_first': firstSpotId,
      'p_second': secondSpotId,
      'p_editor': true,
    });
    final data = Map<String, dynamic>.from(raw as Map);
    if (data['code'] != 200) {
      throw BlueprintCommandRejection(
          (data['code'] as num?)?.toInt() ?? 409, data);
    }
    final preview = BlueprintSeatSwapPreview.fromJson(data,
        organizationId: organizationId, unitId: unitId);
    if (preview.occasionId != occasionId ||
        preview.blueprintId != blueprintId ||
        preview.firstSpotId != firstSpotId ||
        preview.secondSpotId != secondSpotId) {
      throw const FormatException('Seat swap scope changed');
    }
    return preview;
  }

  @override
  Future<bool> recoverSwap(
      {required int occasionId,
      required int organizationId,
      int? unitId,
      required int blueprintId}) async {
    if (_transport.principalBinding == null) return false;
    final pending = await _transport.pendingIntent('swap_blueprint_seats', {
      'p_occasion': occasionId,
      'p_unit': unitId,
    });
    if (pending == null) return false;
    final request = jsonDecode(pending.requestJson) as Map;
    if (request['p_occasion'] != occasionId ||
        request['p_organization'] != organizationId ||
        request['p_unit'] != unitId ||
        request['p_blueprint'] != blueprintId) {
      throw BlueprintCommandRejection(
          409, {'reason': 'BLUEPRINT_SWAP_RECOVERY_REQUIRED'});
    }
    // Resume only the already approved, persisted request. Never preview and
    // swap the newly observed inverse assignment after an uncertain response.
    final raw = await _transport.resume(pending);
    if (raw is Map && raw['code'] == 410) {
      throw BlueprintCommandRejection(
          410, {'reason': 'BLUEPRINT_SWAP_RECOVERY_REQUIRED'});
    }
    final response = ClientCommandResponse.from(raw);
    if (response.code != 200) {
      throw BlueprintCommandRejection(response.code, response.data);
    }
    await response.applyConfirmedReplacements();
    return true;
  }

  @override
  Future<void> swapSpots(BlueprintSeatSwapPreview preview) async {
    final response = ClientCommandResponse.from(
        await _transport.invoke('swap_blueprint_seats', {
      'p_occasion': preview.occasionId,
      'p_organization': preview.organizationId,
      'p_unit': preview.unitId,
      'p_blueprint': preview.blueprintId,
      'p_first': preview.firstSpotId,
      'p_second': preview.secondSpotId,
      'p_source_spots': preview.sourceSpotIds,
      'p_target_spots': preview.targetSpotIds,
      'p_expected_revision': preview.layoutRevision,
      'p_confirmation_hash': preview.confirmationHash,
      'p_editor': true,
    }));
    if (response.code != 200) {
      throw BlueprintCommandRejection(response.code, response.data);
    }
    await response.applyConfirmedReplacements();
  }
}
