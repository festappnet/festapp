import 'package:test/test.dart';
import 'package:festapp_core/eshop.dart';
import 'package:timezone/data/latest.dart' as tzdata;
import '../support/occasion_report_fixture.dart';

void main() {
  setUpAll(tzdata.initializeTimeZones);
  test(
    'Stripe subsets, dispute availability and unattributed external amounts survive snapshot parsing',
    () {
      final response = reportResponse();
      response['report']['money_by_currency'][0].addAll({
        'stripe_received': '50.00',
        'stripe_refunded': '20.00',
        'disputed': '10.00',
        'available_after_disputes': '85.00',
        'external_unattributed': '25.00',
      });
      final report = OccasionReport.fromResponse(response);
      expect(report.money.first.amounts['stripe_received'], '50.00');
      expect(report.money.first.amounts['disputed'], '10.00');
      expect(report.money.first.amounts['external_unattributed'], '25.00');
      expect(
        () => report.money.first.amounts['stripe_received'] = '0',
        throwsUnsupportedError,
      );
    },
  );
  test(
    'ticket history counts people independently of orders and follows validity',
    () {
      final response = reportResponse();
      response['report']['timeline']['tickets'] = [
        {'day': '2026-10-01', 'currency': 'CZK', 'count': 24},
      ];
      response['report']['valid']['ticket_days'] = [
        {'day': '2026-10-01', 'currency': 'CZK', 'count': 23},
      ];
      final report = OccasionReport.fromResponse(response);
      expect(report.ticketDays.single.count, 24);
      expect(report.onlyValid().ticketDays.single.count, 23);
      expect(report.orderDays.first.count, 2);
      response['report']['timeline'].remove('tickets');
      response['report']['valid'].remove('ticket_days');
      final legacy = OccasionReport.fromResponse(response);
      expect(legacy.hasTicketTimeline, isFalse);
      expect(legacy.onlyValid().hasTicketTimeline, isFalse);
    },
  );
  test('report snapshots own response collections across filtered views', () {
    final response = reportResponse();
    final report = OccasionReport.fromResponse(response);
    response['report']['orders']['total'] = 999;
    expect(report.orders.total, isNot(999));
    expect(report.onlyValid().orders.total, 3);
    expect(() => report.money.clear(), throwsUnsupportedError);
    expect(() => report.orders.states.clear(), throwsUnsupportedError);
    final rates = ReportExchangeRates.fromJson({
      'source': 'CNB',
      'base': 'CZK',
      'date': '2026-10-02',
      'rates': <String, dynamic>{},
    });
    expect(() => rates.rates.clear(), throwsUnsupportedError);
  });
  test('report period ends with occasion but preserves later activity', () {
    final today = DateTime.utc(2026, 10, 3);
    final end = DateTime.utc(2026, 2, 20);
    expect(
      reportTimelineEnd(
        today: today,
        lastActivity: DateTime.utc(2026, 2, 1),
        occasionEnd: end,
      ),
      end,
    );
    expect(
      reportTimelineEnd(
        today: today,
        lastActivity: DateTime.utc(2026, 3, 5),
        occasionEnd: end,
      ),
      DateTime.utc(2026, 3, 5),
    );
    expect(
      reportTimelineEnd(
        today: today,
        lastActivity: end,
        occasionEnd: DateTime.utc(2026, 12, 1),
      ),
      today,
    );
    expect(reportTimelineEnd(today: today, lastActivity: end), end);
    expect(
      reportDay(DateTime.parse('2026-03-29T22:30:00Z')),
      DateTime.utc(2026, 3, 30),
    );
  });
  test('CNB conversion rounds exact cents and respects quoted quantities', () {
    final rates = ReportExchangeRates.fromJson({
      'source': 'CNB',
      'base': 'CZK',
      'date': '2026-10-02',
      'rates': {
        'EUR': {'amount': '1', 'rate': '24.5'},
        'JPY': {'amount': '100', 'rate': '14.123'},
      },
    });
    expect(rates.toCzk(BigInt.from(100), 'EUR'), BigInt.from(2450));
    expect(rates.toCzk(BigInt.one, 'EUR'), BigInt.from(25));
    expect(rates.toCzk(BigInt.from(10000), 'JPY'), BigInt.from(1412));
    expect(
      rates.toCzk(BigInt.parse('1234567890123456789012'), 'EUR'),
      BigInt.parse('30246913308024691330794'),
    );
    expect(() => rates.toCzk(BigInt.one, 'XXX'), throwsFormatException);
  });
  test(
    'contract preserves decimal precision and rejects unavailable reports',
    () {
      final r = reportFixture();
      expect(
        r.money.first.amounts['current_order_value'],
        '12345678901234567890.12',
      );
      expect(r.products.map((p) => p.id), ['1', '2']);
      expect(reportFixture(empty: true).orders.total, 0);
      expect(
        () => OccasionReport.fromResponse({'code': 403}),
        throwsA(isA<ReportUnavailable>()),
      );
      expect(
        () => OccasionReport.fromResponse({'code': 200, 'data': 'old backend'}),
        throwsA(isA<ReportUnavailable>()),
      );
      final unsupported = reportResponse();
      unsupported['report']['schema_version'] = 2;
      expect(
        () => OccasionReport.fromResponse(unsupported),
        throwsA(isA<ReportUnavailable>()),
      );
      final bad = reportResponse();
      bad['report']['orders']['total'] = 9;
      expect(
        () => OccasionReport.fromResponse(bad),
        throwsA(isA<ReportUnavailable>()),
      );
    },
  );
}
