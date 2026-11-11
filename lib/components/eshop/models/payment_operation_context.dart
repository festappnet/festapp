/// Authorized capability and exact financial projection from the payment owner.
/// Read-only QR availability is separate from capabilities that record money.
class PaymentOperationContext {
  const PaymentOperationContext({
    this.gross = '0',
    this.refunded = '0',
    this.net = '0',
    this.pending = '0',
    this.available = '0',
    this.currency = '',
    this.methods = const [],
    this.requests = const [],
  });
  final String gross, refunded, net, pending, available, currency;
  final List<PaymentOperationMethod> methods;
  final List<Map<String, dynamic>> requests;
  bool get canRecord => methods.any((m) => m.record);
  bool get canRefund =>
      methods.any((m) => m.refund || m.instructions) ||
      requests.any(
        (r) =>
            const {
                  'pending',
                  'action_required',
                  'unknown',
                  'processing',
                }.contains(r['status']) &&
                r['canReopen'] == true ||
            r['canCorrect'] == true,
      );
  factory PaymentOperationContext.fromJson(Map value) =>
      PaymentOperationContext(
        gross: '${value['gross'] ?? 0}',
        refunded: '${value['refunded'] ?? 0}',
        net: '${value['net'] ?? 0}',
        pending: '${value['pending'] ?? 0}',
        available: '${value['available'] ?? 0}',
        currency: '${value['currency'] ?? ''}',
        methods: List.unmodifiable(
          (value['methods'] as List? ?? const []).whereType<Map>().map(
            PaymentOperationMethod.fromJson,
          ),
        ),
        requests: List.unmodifiable(
          (value['requests'] as List? ?? const []).whereType<Map>().map(
            (r) => Map<String, dynamic>.from(r),
          ),
        ),
      );
}

class PaymentOperationMethod {
  const PaymentOperationMethod({
    required this.id,
    required this.displayName,
    this.refund = false,
    this.instructions = false,
    this.record = false,
    this.verification = '',
    this.reason,
  });
  final String id, displayName, verification;
  final bool refund, record, instructions;
  final String? reason;
  factory PaymentOperationMethod.fromJson(Map value) => PaymentOperationMethod(
    id: '${value['id']}',
    displayName: '${value['displayName'] ?? value['id']}',
    refund: value['refund'] == true,
    instructions: value['instructions'] == true,
    record: value['record'] == true,
    verification: '${value['verification'] ?? ''}',
    reason: value['reason']?.toString(),
  );
}
