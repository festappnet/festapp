import 'package:flutter_test/flutter_test.dart';
import 'package:fstapp/components/eshop/models/order_model.dart';
import 'package:fstapp/components/eshop/models/ticket_model.dart';
import 'package:fstapp/components/scan/scan_field_mappings.dart';

void main() {
  group('getFieldValue', () {
    test('returns value when field exists', () {
      final order = OrderModel();
      order.data = {
        'fields': [
          {'735': 'Student'},
        ],
      };
      expect(getFieldValue(order, '735'), 'Student');
    });

    test('returns null when data is null', () {
      final order = OrderModel();
      order.data = null;
      expect(getFieldValue(order, '735'), isNull);
    });

    test('returns null when fields key is missing', () {
      final order = OrderModel();
      order.data = {'other': 'value'};
      expect(getFieldValue(order, '735'), isNull);
    });

    test('returns null when fields is not a list', () {
      final order = OrderModel();
      order.data = {'fields': 'not a list'};
      expect(getFieldValue(order, '735'), isNull);
    });

    test('returns null when field ID not found', () {
      final order = OrderModel();
      order.data = {
        'fields': [
          {'999': 'Other'},
        ],
      };
      expect(getFieldValue(order, '735'), isNull);
    });

    test('returns null for empty string value', () {
      final order = OrderModel();
      order.data = {
        'fields': [
          {'735': ''},
        ],
      };
      expect(getFieldValue(order, '735'), isNull);
    });

    test('returns null for null value in field', () {
      final order = OrderModel();
      order.data = {
        'fields': [
          {'735': null},
        ],
      };
      expect(getFieldValue(order, '735'), isNull);
    });

    test('handles multiple field entries', () {
      final order = OrderModel();
      order.data = {
        'fields': [
          {'735': 'Student'},
          {'739': 'Vegan'},
        ],
      };
      expect(getFieldValue(order, '739'), 'Vegan');
    });

    test('returns null for empty fields list', () {
      final order = OrderModel();
      order.data = {'fields': []};
      expect(getFieldValue(order, '735'), isNull);
    });

    test('skips non-map entries in fields list', () {
      final order = OrderModel();
      order.data = {
        'fields': [
          'not a map',
          {'735': 'Student'},
        ],
      };
      expect(getFieldValue(order, '735'), 'Student');
    });
  });

  group('getTicketPrice', () {
    test('returns total price from products', () {
      final ticket = TicketModel(id: 1);
      ticket.relatedOrder = OrderModel();
      ticket.relatedOrder!.data = {
        'tickets': [
          {
            'id': 1,
            'products': [
              {'price': '100.0'},
              {'price': '50.5'},
            ],
          },
        ],
      };
      expect(getTicketPrice(ticket), 150.5);
    });

    test('returns null when scannedObject is null', () {
      expect(getTicketPrice(null), isNull);
    });

    test('returns null when relatedOrder is null', () {
      final ticket = TicketModel(id: 1);
      expect(getTicketPrice(ticket), isNull);
    });

    test('returns null when order data is null', () {
      final ticket = TicketModel(id: 1);
      ticket.relatedOrder = OrderModel();
      ticket.relatedOrder!.data = null;
      expect(getTicketPrice(ticket), isNull);
    });

    test('returns null when tickets key missing', () {
      final ticket = TicketModel(id: 1);
      ticket.relatedOrder = OrderModel();
      ticket.relatedOrder!.data = {'other': 'value'};
      expect(getTicketPrice(ticket), isNull);
    });

    test('returns null when ticket ID not found in list', () {
      final ticket = TicketModel(id: 99);
      ticket.relatedOrder = OrderModel();
      ticket.relatedOrder!.data = {
        'tickets': [
          {
            'id': 1,
            'products': [
              {'price': '100.0'},
            ],
          },
        ],
      };
      expect(getTicketPrice(ticket), isNull);
    });

    test('returns 0 for empty products list', () {
      final ticket = TicketModel(id: 1);
      ticket.relatedOrder = OrderModel();
      ticket.relatedOrder!.data = {
        'tickets': [
          {
            'id': 1,
            'products': [],
          },
        ],
      };
      expect(getTicketPrice(ticket), 0.0);
    });

    test('returns null when no products key in ticket data', () {
      final ticket = TicketModel(id: 1);
      ticket.relatedOrder = OrderModel();
      ticket.relatedOrder!.data = {
        'tickets': [
          {'id': 1},
        ],
      };
      expect(getTicketPrice(ticket), isNull);
    });

    test('skips products without price field', () {
      final ticket = TicketModel(id: 1);
      ticket.relatedOrder = OrderModel();
      ticket.relatedOrder!.data = {
        'tickets': [
          {
            'id': 1,
            'products': [
              {'price': '100.0'},
              {'name': 'no price'},
            ],
          },
        ],
      };
      expect(getTicketPrice(ticket), 100.0);
    });

    test('handles non-numeric price gracefully', () {
      final ticket = TicketModel(id: 1);
      ticket.relatedOrder = OrderModel();
      ticket.relatedOrder!.data = {
        'tickets': [
          {
            'id': 1,
            'products': [
              {'price': 'abc'},
              {'price': '50.0'},
            ],
          },
        ],
      };
      expect(getTicketPrice(ticket), 50.0);
    });
  });

  group('specificFieldMappings', () {
    test('contains expected field IDs', () {
      expect(specificFieldMappings.containsKey('735'), isTrue);
      expect(specificFieldMappings.containsKey('739'), isTrue);
      expect(specificFieldMappings.containsKey('615'), isTrue);
    });

    test('maps to non-empty labels', () {
      for (final value in specificFieldMappings.values) {
        expect(value, isNotEmpty);
      }
    });
  });
}
