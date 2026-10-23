import 'dart:convert';
import 'package:festapp_core/sync.dart';
import 'package:fstapp/data_services/client_sync/client_command_replacements.dart';
import 'package:fstapp/components/blueprint/blueprint_command_rejection.dart';
import 'package:fstapp/components/blueprint/blueprint_seat_order_preview.dart';
import 'package:fstapp/data_services/client_sync/client_command_identity.dart';
import 'package:fstapp/data_services/client_sync/client_command_transport.dart';
import 'package:http/http.dart' as http;
import 'package:supabase_flutter/supabase_flutter.dart';

/// The allocation has committed, but its original payment preparation is pending.
/// Keeping this as a transport failure preserves the exact durable intent.
class SeatOrderPreparationPending extends http.ClientException {
  SeatOrderPreparationPending(this.orderId)
      : super('PAYMENT_PREPARATION_PENDING_RETRY_SAME_COMMAND');
  final int orderId;
}

class SeatOrderOutcome {
  SeatOrderOutcome._(this.orderId, this.orderSymbol, this.fulfillmentStatus);
  final int orderId;
  final String orderSymbol, fulfillmentStatus;
}

abstract interface class SeatOrderCommands {
  Future<BlueprintSeatOrderRequirements> requirements(
      BlueprintSeatOrderRequest request);
  Future<BlueprintSeatOrderPreview> preview(
      BlueprintSeatOrderRequirements requirements, Map<String, dynamic> input);
  Future<SeatOrderOutcome> create(BlueprintSeatOrderPreview preview);
  Future<SeatOrderOutcome?> recover(BlueprintSeatOrderRequest request);
}

class SupabaseSeatOrderCommands implements SeatOrderCommands {
  SupabaseSeatOrderCommands(SupabaseClient client)
      : _transport = ClientCommandTransport(
          (name, params) async {
            if (name != _operation)
              throw StateError('Unsupported seat order command');
            final response = await _invokeEdge(client, {
              'commandId': params['p_command_id'],
              'clientId': await ClientCommandIdentity.clientId(),
              'replacement': {
                'spotIds': params['p_spots'],
                'inputData': params['p_input'],
                'confirmation': {
                  'actorId': params['p_expected_actor'],
                  'occasionId': params['p_occasion'],
                  'organizationId': params['p_organization'],
                  'unitId': params['p_unit'],
                  'blueprintId': params['p_blueprint'],
                  'targetSpotIds': params['p_target_spots'],
                  'affectedSpotIds': params['p_affected_spots'],
                  'blueprints': params['p_blueprints'],
                  'confirmationHash': params['p_confirmation_hash'],
                  'editor': true,
                },
              },
            });
            return decodeEdgeResponse(
                response.data, params['p_command_id'] as String);
          },
          principalProvider: () =>
              '${client.rest.url}:${client.auth.currentUser?.id ?? 'anonymous'}',
        ),
        _read = ((name, params) => client.rpc(name, params: params)),
        _legacyRecovery = ((preview) async {
          final principal =
              '${client.rest.url}:${client.auth.currentUser?.id ?? 'anonymous'}';
          if (principal != preview.principalBinding)
            throw StateError('COMMAND_PRINCIPAL_CHANGED');
          final payload = {
            'spotIds': preview.request.spotIds.toList()..sort(),
            'inputData': preview.inputData
          };
          final command =
              await ClientCommandIdentity.pendingLegacyOrderReplacement(payload,
                  principalBinding: principal);
          if (command == null) return null;
          FunctionResponse response;
          try {
            response = await _invokeEdge(client, {
              'replacement': payload,
              'commandId': command,
              'clientId': await ClientCommandIdentity.clientId()
            });
          } finally {
            if (principal !=
                '${client.rest.url}:${client.auth.currentUser?.id ?? 'anonymous'}')
              throw StateError('COMMAND_PRINCIPAL_CHANGED');
          }
          final data = response.data;
          if (data is Map && data['code'] == 410) {
            throw BlueprintCommandRejection(
                410, {'reason': 'BLUEPRINT_ORDER_RECOVERY_REQUIRED'});
          }
          if (data is! Map || data['code'] != 200)
            throw http.ClientException('LEGACY_ORDER_RECOVERY_PENDING');
          final ticketOrder = data['ticketOrder'],
              order = ticketOrder is Map ? ticketOrder['order'] : null;
          if (order is! Map ||
              order['id'] is! int ||
              (order['id'] as int) <= 0 ||
              order['order_symbol'] == null)
            throw const FormatException('Invalid legacy order acknowledgement');
          await ClientCommandIdentity.completeIntent(
              'ticket_order_replace', payload,
              commandId: command, principalBinding: principal);
          return SeatOrderOutcome._(
              order['id'] as int, order['order_symbol'].toString(), 'ready');
        });

  SupabaseSeatOrderCommands.withTransport(this._transport,
      {required ClientCommandRpc readRpc,
      Future<SeatOrderOutcome?> Function(BlueprintSeatOrderPreview)?
          legacyRecovery})
      : _read = readRpc,
        _legacyRecovery = legacyRecovery;
  static const _operation = 'create_blueprint_seat_order';
  static Future<FunctionResponse> _invokeEdge(
      SupabaseClient client, Map<String, dynamic> body) async {
    try {
      return await client.functions.invoke('send-ticket-order', body: body);
    } on FunctionsFetchException {
      throw http.ClientException(
          'SEAT_ORDER_RESPONSE_UNAVAILABLE_RETRY_SAME_COMMAND');
    } on FunctionsRelayException catch (error) {
      if (error.status == 401 || error.status == 403)
        throw const PostgrestException(
            message: 'Seat order authorization denied', code: '42501');
      throw http.ClientException(
          'SEAT_ORDER_RESPONSE_UNAVAILABLE_RETRY_SAME_COMMAND');
    } on FunctionsHttpException catch (error) {
      if (error.status == 401 || error.status == 403) {
        throw const PostgrestException(
            message: 'Seat order authorization denied', code: '42501');
      }
      if (error.status >= 500 || error.status == 408 || error.status == 429) {
        throw http.ClientException(
            'SEAT_ORDER_RESPONSE_UNAVAILABLE_RETRY_SAME_COMMAND');
      }
      rethrow;
    }
  }

  final ClientCommandTransport _transport;
  final ClientCommandRpc _read;
  final Future<SeatOrderOutcome?> Function(BlueprintSeatOrderPreview)?
      _legacyRecovery;

  /// Public for transport tests: the production HTTP binding uses this decoder.
  static Object? decodeEdgeResponse(Object? raw, String commandId) {
    if (raw is! Map) throw http.ClientException('UPSTREAM_CONTRACT_FAILURE');
    if (raw['code'] == 503) {
      final committed = raw['committed'];
      if (committed is Map) {
        final receipt = ClientCommandResponse.from(committed);
        if (receipt.code != 200 || receipt.mutation['commandId'] != commandId)
          throw const FormatException('Command response identity mismatch');
        final order = receipt.data['order'];
        final id = order is Map ? order['id'] : null;
        if (id is! int || id <= 0)
          throw const FormatException('Invalid committed seat order');
        throw SeatOrderPreparationPending(id);
      }
      throw http.ClientException('UPSTREAM_TEMPORARY_FAILURE');
    }
    if (raw['errorCode'] != null) {
      throw PostgrestException(
          message: 'Seat order command rejected',
          code: raw['errorCode'].toString());
    }
    if (raw['code'] == 200) {
      final fulfillment = raw['fulfillment'];
      final receipt = ClientCommandResponse.from(raw);
      final order = receipt.data['order'];
      if (receipt.mutation['commandId'] != commandId ||
          fulfillment is! Map ||
          !const {'ready', 'closed'}.contains(fulfillment['status']) ||
          order is! Map ||
          order['id'] is! int ||
          (order['id'] as int) <= 0 ||
          order['order_symbol'] == null)
        throw const FormatException(
            'Invalid order fulfillment acknowledgement');
    }
    return raw;
  }

  Future<Object?> _readBound(
      Map<String, dynamic> params, String? principal) async {
    try {
      if (principal != _transport.principalBinding)
        throw StateError('COMMAND_PRINCIPAL_CHANGED');
      return await _read('preview_blueprint_seat_order', params);
    } finally {
      if (principal != _transport.principalBinding)
        throw StateError('COMMAND_PRINCIPAL_CHANGED');
    }
  }

  Map<String, dynamic> _previewData(Object? raw) {
    final data = Map<String, dynamic>.from(raw as Map);
    if (data['code'] != 200)
      throw BlueprintCommandRejection(
          (data['code'] as num?)?.toInt() ?? 409, data);
    return data;
  }

  @override
  Future<BlueprintSeatOrderRequirements> requirements(
      BlueprintSeatOrderRequest request) async {
    final principal = _transport.principalBinding;
    return BlueprintSeatOrderRequirements.fromJson(
        _previewData(await _readBound(request.parameters, principal)),
        request: request,
        principalBinding: principal);
  }

  @override
  Future<BlueprintSeatOrderPreview> preview(
      BlueprintSeatOrderRequirements requirements,
      Map<String, dynamic> input) async {
    return BlueprintSeatOrderPreview.fromJson(
        _previewData(await _readBound(
            {...requirements.request.parameters, 'p_input': input},
            requirements.principalBinding)),
        requirements: requirements,
        inputData: input,
        principalBinding: _transport.principalBinding);
  }

  Future<SeatOrderOutcome> _finish(
      Future<Object?> Function() invoke, String? principal) async {
    Object? raw;
    try {
      if (principal != _transport.principalBinding)
        throw StateError('COMMAND_PRINCIPAL_CHANGED');
      raw = await invoke();
    } finally {
      if (principal != _transport.principalBinding)
        throw StateError('COMMAND_PRINCIPAL_CHANGED');
    }
    // Tombstones intentionally are not terminal acknowledgement envelopes.
    // Keep their original journal; the shared success parser rejects them.
    if (raw is Map && raw['code'] == 410) {
      throw BlueprintCommandRejection(
          410, {'reason': 'BLUEPRINT_ORDER_RECOVERY_REQUIRED'});
    }
    final response = ClientCommandResponse.from(raw);
    if (response.code != 200)
      throw BlueprintCommandRejection(response.code, response.data);
    final order = response.data['order'];
    if (order is! Map ||
        order['id'] is! int ||
        (order['id'] as int) <= 0 ||
        order['order_symbol'] == null)
      throw const FormatException('Invalid confirmed seat order');
    final fulfillment = (raw as Map)['fulfillment'];
    final status = fulfillment is Map ? fulfillment['status'] : null;
    if (!const {'ready', 'closed'}.contains(status))
      throw const FormatException('Invalid order fulfillment acknowledgement');
    await response.applyConfirmedReplacements();
    return SeatOrderOutcome._(
        order['id'] as int, order['order_symbol'].toString(), status as String);
  }

  @override
  Future<SeatOrderOutcome> create(BlueprintSeatOrderPreview preview) async {
    if (preview.principalBinding != _transport.principalBinding)
      throw StateError('COMMAND_PRINCIPAL_CHANGED');
    final legacy = await _legacyRecovery?.call(preview);
    if (legacy != null) return legacy;
    return _finish(() => _transport.invoke(_operation, preview.parameters),
        preview.principalBinding);
  }

  @override
  Future<SeatOrderOutcome?> recover(BlueprintSeatOrderRequest request) async {
    final principal = _transport.principalBinding;
    if (principal == null) return null;
    final pending =
        await _transport.pendingIntent(_operation, request.parameters);
    if (principal != _transport.principalBinding)
      throw StateError('COMMAND_PRINCIPAL_CHANGED');
    if (pending == null) return null;
    final original = jsonDecode(pending.requestJson) as Map;
    if (original['p_organization'] != request.organizationId ||
        original['p_blueprint'] != request.blueprintId ||
        original['p_occasion'] != request.occasionId ||
        original['p_unit'] != request.unitId) {
      throw BlueprintCommandRejection(
          409, {'reason': 'BLUEPRINT_ORDER_RECOVERY_REQUIRED'});
    }
    return _finish(() => _transport.resume(pending), principal);
  }
}
