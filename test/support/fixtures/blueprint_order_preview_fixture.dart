import 'package:fstapp/components/blueprint/blueprint_seat_order_preview.dart';
import 'package:fstapp/components/eshop/seat_order_commands.dart';
import 'package:fstapp/data_services/client_sync/client_command_transport.dart';
import 'client_command_response_fixture.dart';

BlueprintSeatOrderRequest seatOrderRequestFixture() =>
    BlueprintSeatOrderRequest(
        occasionId: 9,
        organizationId: 3,
        unitId: 4,
        blueprintId: 5,
        spotIds: [71]);
Map<String, dynamic> seatOrderRequirementsJson(
        {List<Map<String, dynamic>> fields = const []}) =>
    {
      'code': 200,
      'mode': 'requirements',
      'actorId': '00000000-0000-4000-8000-000000000002',
      'occasionId': 9,
      'blueprintId': 5,
      'requestedSpotIds': [71],
      'spotIds': [71],
      'affectedSpotIds': [71],
      'items': [
        {
          'spotId': 71,
          'title': 'A1',
          'productTitle': 'Seat',
          'amount': '100.00',
          'currencyCode': 'CZK'
        }
      ],
      'conflicts': [],
      'requiredFields': fields,
      'phonePrefixes': [],
      'seatSubtotal': '100.00',
      'currencyCode': 'CZK',
      'formKey': '00000000-0000-4000-8000-000000000001',
    };
Map<String, dynamic> seatOrderQuoteJson() => {
      ...seatOrderRequirementsJson(),
      'mode': 'quote',
      'confirmationHash': List.filled(64, 'a').join(),
      'quote': {
        'spotIds': [71],
        'affectedSpotIds': [71],
        'releasedSpotIds': [],
        'blueprints': [
          {'id': 5, 'revision': 3}
        ],
        'seats': [
          {
            'spotId': 71,
            'blueprintId': 5,
            'blueprintTitle': 'Hall',
            'title': 'A1',
            'productTitle': 'Seat',
            'stateBefore': 'available',
            'stateAfter': 'ordered',
            'previousOrderId': null,
            'previousTicketId': null
          }
        ],
        'orders': [],
        'formKey': '00000000-0000-4000-8000-000000000001',
        'newOrder': {
          'amount': '100.00',
          'currencyCode': 'CZK',
          'state': 'ordered',
          'paymentMethod': 'bank',
          'ticketCount': 1,
          'products': [
            {
              'spotId': 71,
              'productId': 20,
              'title': 'Seat',
              'amount': '100.00',
              'currencyCode': 'CZK'
            }
          ]
        },
      },
    };
Map<String, dynamic> seatOrderReceiptFixture(String commandId) => {
      ...commandResponseFixture(commandId, data: {
        'code': 200,
        'order': {'id': 101, 'order_symbol': 'TEST101'}
      }),
      'fulfillment': {'status': 'ready'},
    };
SeatOrderCommands seatOrderCommandsFixture(
        {List<Map<String, dynamic>> fields = const [],
        Future<void> Function()? onRequirements,
        Future<void> Function(Map<String, dynamic>)? onQuote,
        Future<void> Function(Map<String, dynamic>)? onCreate}) =>
    SupabaseSeatOrderCommands.withTransport(
        ClientCommandTransport((name, params) async {
      await onCreate?.call(Map<String, dynamic>.from(params['p_input'] as Map));
      return SupabaseSeatOrderCommands.decodeEdgeResponse(
          seatOrderReceiptFixture(params['p_command_id'] as String),
          params['p_command_id'] as String);
    }), readRpc: (name, params) async {
      if (params['p_input'] == null) {
        await onRequirements?.call();
        return seatOrderRequirementsJson(fields: fields);
      }
      await onQuote?.call(Map<String, dynamic>.from(params['p_input'] as Map));
      return seatOrderQuoteJson();
    });
