class ReportOrderDay {
  final DateTime day;
  final int count;
  final String currency;
  ReportOrderDay(Map<String, dynamic> json)
      : day = DateTime.parse('${json['day']}T00:00:00Z'),
        currency = json['currency'] as String,
        count = json['count'] as int {
    if (count < 0) throw const FormatException('Invalid daily orders');
  }
}

class ReportPaymentDay {
  final DateTime day;
  final String currency, received, returned;
  ReportPaymentDay(Map<String, dynamic> json)
      : day = DateTime.parse('${json['day']}T00:00:00Z'),
        currency = json['currency'] as String,
        received = json['received'] as String,
        returned = json['returned'] as String {
    if ([
      received,
      returned,
    ].any((v) => !RegExp(r'^\d+(\.\d{1,2})?$').hasMatch(v))) {
      throw const FormatException('Invalid daily payment');
    }
  }
}

class ReportUnavailable implements Exception {
  final int? code;
  const ReportUnavailable(this.code);
}

class ReportCounts {
  final int total;
  final Map<String, int> states;
  ReportCounts(Map<String, dynamic> json)
      : total = json['total'] as int,
        states = {
          for (final s in json['by_state'] as List)
            s['state'] as String: s['count'] as int,
        } {
    if (total < 0 ||
        states.values.any((v) => v < 0) ||
        states.values.fold(0, (int a, b) => a + b) != total) {
      throw const FormatException('Invalid report counts');
    }
  }
}

class ReportMoney {
  final String currency;
  final bool hasDeposits;
  final Map<String, String> amounts;
  ReportMoney(Map<String, dynamic> json)
      : currency = json['currency'] as String,
        hasDeposits = json['has_deposits'] as bool,
        amounts = {
          for (final key in const [
            'current_order_value',
            'received',
            'returned',
            'net_received',
            'manual_received',
            'other_received',
            'deposit_received_gross',
            'beyond_deposit_received_gross',
          ])
            key: json[key] as String,
        } {
    if (amounts.values.any((v) => !RegExp(r'^-?\d+(\.\d+)?$').hasMatch(v))) {
      throw const FormatException('Invalid decimal amount');
    }
  }
}

class ReportProduct {
  final String id, title;
  final String? typeId, typeTitle;
  final int count;
  ReportProduct(Map<String, dynamic> json)
      : id = json['product_id'] as String,
        title = json['product_title'] as String,
        typeId = json['type_id'] as String?,
        typeTitle = json['type_title'] as String?,
        count = json['confirmed_count'] as int;
}

class OccasionReport {
  final Map<String, dynamic> _source;

  OccasionReport onlyValid() {
    final valid = Map<String, dynamic>.from(_source['valid'] as Map);
    return OccasionReport._({
      ..._source,
      'orders': valid['orders'],
      'tickets': valid['tickets'],
      if (_source['timeline'] != null)
        'timeline': {...Map<String, dynamic>.from(_source['timeline'] as Map), 'orders': valid['order_days']},
    }, text);
  }

  final String text, occasionId, title;
  final DateTime generatedAt;
  final ReportCounts orders, tickets;
  final int spotsTotal, spotsOccupied, spotsFree;
  final List<ReportMoney> money;
  final List<ReportProduct> products;
  final Map<String, int> warnings;
  final List<ReportOrderDay> orderDays;
  final List<ReportPaymentDay> paymentDays;
  final bool hasTimeline;

  OccasionReport._(Map<String, dynamic> r, this.text)
      : _source = r,
        hasTimeline = r['timeline'] != null,
        orderDays = [
          for (final d in r['timeline']?['orders'] ?? [])
            ReportOrderDay(Map<String, dynamic>.from(d)),
        ],
        paymentDays = [
          for (final d in r['timeline']?['payments'] ?? [])
            ReportPaymentDay(Map<String, dynamic>.from(d)),
        ],
        occasionId = r['occasion']['id'] as String,
        title = r['occasion']['title'] as String,
        generatedAt = DateTime.parse(r['generated_at'] as String),
        orders = ReportCounts(Map<String, dynamic>.from(r['orders'])),
        tickets = ReportCounts(Map<String, dynamic>.from(r['tickets'])),
        spotsTotal = r['spots']['total'] as int,
        spotsOccupied = r['spots']['occupied'] as int,
        spotsFree = r['spots']['free'] as int,
        money = [
          for (final m in r['money_by_currency'])
            ReportMoney(Map<String, dynamic>.from(m)),
        ],
        products = [
          for (final p in r['products'])
            ReportProduct(Map<String, dynamic>.from(p)),
        ],
        warnings = {
          for (final w in r['warnings']) w['code'] as String: w['count'] as int,
        } {
    if (spotsOccupied < 0 ||
        spotsFree < 0 ||
        spotsTotal != spotsOccupied + spotsFree) {
      throw const FormatException('Invalid report spots');
    }
  }

  factory OccasionReport.fromResponse(dynamic response) {
    if (response is! Map || response['code'] != 200) {
      throw ReportUnavailable(
        response is Map ? response['code'] as int? : null,
      );
    }
    try {
      final r = Map<String, dynamic>.from(response['report'] as Map);
      if (r['schema_version'] != 1) {
        throw const FormatException('Unsupported report');
      }
      final report = OccasionReport._(r, response['data'] as String);
      report.onlyValid(); // Validate the filtered snapshot before exposing it to the UI.
      return report;
    } catch (_) {
      throw const ReportUnavailable(null);
    }
  }
}
