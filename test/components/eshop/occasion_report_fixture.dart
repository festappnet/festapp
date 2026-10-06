import 'package:fstapp/components/eshop/models/occasion_report_model.dart';

Map<String, dynamic> reportResponse({String id = '1', bool empty = false}) => {
      'code': 200,
      'data':
          'Report $id\nPříliš dlouhý název akce a produktu pro úzký telefon\nČistý příjem: 12345678901234567890.12 CZK',
      'report': {
        'schema_version': 1,
        'valid': {
          'orders': {'total': empty ? 0 : 3, 'by_state': empty ? [] : [{'state': 'paid', 'count': 2}, {'state': 'unknown', 'count': 1}]},
          'tickets': {'total': empty ? 0 : 2, 'by_state': empty ? [] : [{'state': 'paid', 'count': 2}]},
          'order_days': empty ? [] : [{'day': '2026-10-01', 'currency': 'CZK', 'count': 2}, {'day': '2026-10-03', 'currency': 'EUR', 'count': 1}],
        },
        'occasion': {
          'id': id,
          'title': 'Testovací akce $id s dlouhým názvem pro mobilní obrazovku'
        },
        'generated_at': '2026-10-03T12:00:00Z',
        'timeline': {
          'order_timezone': 'Europe/Prague',
          'payment_date_basis': 'transaction_date',
          'orders': empty
              ? []
              : [
                  {'day': '2026-10-01', 'currency': 'CZK', 'count': 2},
                  {'day': '2026-10-03', 'currency': 'EUR', 'count': 1},
                ],
          'payments': empty
              ? []
              : [
                  {
                    'day': '2026-10-01',
                    'currency': 'CZK',
                    'received': '25.00',
                    'returned': '0'
                  },
                  {
                    'day': '2026-10-03',
                    'currency': 'CZK',
                    'received': '50.00',
                    'returned': '10.00'
                  },
                  {
                    'day': '2026-10-02',
                    'currency': 'EUR',
                    'received': '15.00',
                    'returned': '0'
                  },
                ],
        },
        'spots': {
          'total': empty ? 0 : 3,
          'occupied': empty ? 0 : 2,
          'free': empty ? 0 : 1
        },
        'orders': {
          'total': empty ? 0 : 3,
          'by_state': empty
              ? []
              : [
                  {'state': 'paid', 'count': 2},
                  {'state': 'unknown', 'count': 1}
                ]
        },
        'tickets': {
          'total': empty ? 0 : 2,
          'by_state': empty
              ? []
              : [
                  {'state': 'paid', 'count': 2}
                ]
        },
        'money_by_currency': empty
            ? []
            : [
                for (final currency in ['CZK', 'EUR'])
                  {
                    'currency': currency,
                    'has_deposits': true,
                    'current_order_value': '12345678901234567890.12',
                    'received': '200.00',
                    'returned': '20.00',
                    'net_received': '180.00',
                    'manual_received': '100.00',
                    'other_received': '100.00',
                    'deposit_received_gross': '50.00',
                    'beyond_deposit_received_gross': '150.00',
                  }
              ],
        'products': empty
            ? []
            : [
                for (final id in ['1', '2'])
                  {
                    'type_id': null,
                    'type_title': null,
                    'product_id': id,
                    'product_title':
                        'Velmi dlouhý shodný název produktu v potvrzené objednávce s uhrazenou zálohou',
                    'confirmed_count': 2,
                  }
              ],
        'warnings': empty
            ? []
            : [
                {'code': 'missing_order_price', 'count': 1}
              ],
      },
    };
OccasionReport reportFixture({String id = '1', bool empty = false}) =>
    OccasionReport.fromResponse(reportResponse(id: id, empty: empty));
