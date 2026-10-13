import 'package:flutter_test/flutter_test.dart';
import 'package:trina_grid/trina_grid.dart';
import 'package:fstapp/components/eshop/eshop_columns.dart';
import 'package:fstapp/components/eshop/order_grid_filters.dart';
import 'package:fstapp/components/eshop/db_orders.dart';
import 'package:fstapp/components/eshop/db_tickets.dart';
import 'package:fstapp/components/eshop/models/order_model.dart';
import 'package:fstapp/components/eshop/models/ticket_model.dart';

void main() {
  TicketModel ticket(int id, String state, {String? symbol}) => TicketModel(
        id: id,
        state: state,
        ticketSymbol: symbol,
        createdAt: DateTime.utc(2026, 10, 13, 10, id % 60),
        relatedProducts: [],
      );
  test(
      'ticket tab loads regular plus waiting and withdrawn tickets without product snapshots',
      () {
    final regular = ticket(1, 'paid', symbol: 'VALID1');
    final waiting = ticket(8836, 'waitlisted');
    final withdrawn = ticket(8837, 'storno');
    final orders = [
      OrderModel(id: 1, orderSymbol: 'REGULAR', relatedTickets: [
        regular
      ], data: {
        'tickets': [
          {
            'id': 1,
            'ticket_symbol': 'VALID1',
            'products': [
              {'price': 100}
            ]
          },
        ]
      }),
      OrderModel(
          id: 2,
          orderSymbol: 'WAITING',
          relatedTickets: [waiting],
          data: {'email': 'waiting@example.invalid'}),
      OrderModel(
          id: 3,
          orderSymbol: '9W6L1I6R4V',
          relatedTickets: [withdrawn],
          data: {'email': 'withdrawn@example.invalid'}),
    ];
    final rows = DbTickets.ticketsFromOrdersBundle(
        ReservationsBundle(orders: orders, forms: []));
    expect(rows.map((row) => row.id).toSet(), {1, 8836, 8837});
    expect(regular.totalPrice, 100);
    expect(waiting.totalPrice, isNull);
    expect(withdrawn.totalPrice, isNull);
    expect(withdrawn.ticketSymbol, isNull);
    expect(withdrawn.state, 'storno');
    final gridRows = rows
        .map((ticket) => TrinaRow(cells: {
              EshopColumns.TICKET_ID: TrinaCell(value: ticket.id),
              EshopColumns.TICKET_STATE: TrinaCell(value: ticket.state),
            }))
        .toList();
    expect(gridRows, hasLength(3),
        reason: 'All filter keeps every canonical ticket row');
    expect(
        gridRows
            .where(OrderGridFilters.ticketIsNonCancelled)
            .map((row) => row.cells[EshopColumns.TICKET_ID]!.value),
        [1]);
    expect(canDownloadTicket(waiting.state), isFalse);
    expect(canToggleTicketUsage(withdrawn.state), isFalse);
    expect(canDownloadTicket(regular.state), isTrue);
  });

  test('numeric ticket IDs isolate prices when symbols are null', () {
    final first = ticket(10, 'paid');
    final second = ticket(11, 'paid');
    final rows = DbTickets.ticketsFromOrdersBundle(ReservationsBundle(orders: [
      OrderModel(id: 1, orderSymbol: 'GROUP', relatedTickets: [
        first,
        second
      ], data: {
        'tickets': [
          {
            'id': 10,
            'ticket_symbol': null,
            'products': [
              {'price': 100}
            ]
          },
          {
            'id': 11,
            'ticket_symbol': null,
            'products': [
              {'price': 200}
            ]
          },
        ]
      }),
    ], forms: []));
    expect(rows, hasLength(2));
    expect(first.totalPrice, 100);
    expect(second.totalPrice, 200);
  });

  test('empty product snapshot preserves an explicitly zero-priced ticket', () {
    final free = ticket(12, 'paid', symbol: 'FREE');
    final rows = DbTickets.ticketsFromOrdersBundle(ReservationsBundle(orders: [
      OrderModel(id: 1, orderSymbol: 'FREEORDER', relatedTickets: [
        free
      ], data: {
        'tickets': [
          {'id': 12, 'ticket_symbol': 'FREE', 'products': []},
        ]
      }),
    ], forms: []));
    expect(rows.single.totalPrice, 0);
  });
}
