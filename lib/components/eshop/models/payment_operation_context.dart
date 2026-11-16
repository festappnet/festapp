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
    this.invalidIdentity = false,
    this.methods = const [],
    this.requests = const [],
  });
  final String gross, refunded, net, pending, available, currency;
  final bool invalidIdentity;
  final List<PaymentOperationMethod> methods;
  final List<Map<String, dynamic>> requests;
  bool get canViewHistory => requests.isNotEmpty;
  bool get canRecord => !invalidIdentity && methods.any((m) => m.record);
  bool get canRefund =>
      ((double.tryParse(available) ?? 0) > 0 &&
          methods.any((m) => m.canStartRefund)) ||
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
        invalidIdentity: value['invalidIdentity'] != false,
        gross: '${value['gross'] ?? 0}',
        refunded: '${value['refunded'] ?? 0}',
        net: '${value['net'] ?? 0}',
        pending: '${value['pending'] ?? 0}',
        available: '${value['available'] ?? 0}',
        currency: '${value['currency'] ?? ''}',
        methods: List.unmodifiable(
          (value['methods'] as List? ?? const [])
              .whereType<Map>()
              .where((m) => m['visible'] != false)
              .map(PaymentOperationMethod.fromJson),
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
    this.partialRefundSupported = true,
    this.record = false,
    this.verification = '',
    this.reason,
  });
  final String id, displayName, verification;
  final bool refund, record, instructions, partialRefundSupported;
  final String? reason;
  // New bank actions only render instructions; legacy write capability is not a UI action.
  bool get canStartRefund =>
      verification == 'bank_event' ? instructions : refund;
  factory PaymentOperationMethod.fromJson(Map value) => PaymentOperationMethod(
    id: '${value['id']}',
    displayName: '${value['displayName'] ?? value['id']}',
    refund: value['refund'] == true,
    partialRefundSupported: value['partialRefundSupported'] == true,
    instructions: value['instructions'] == true,
    record: value['record'] == true,
    verification: '${value['verification'] ?? ''}',
    reason: value['reason']?.toString(),
  );
}

/// Server-attested purpose/source eligibility; a raw QR payload grants nothing.
bool isBankRefundInstruction(Map value, int orderId, {bool request = false}) =>
    value['method'] == 'bank' &&
    value['verification'] == 'bank_event' &&
    value['purpose'] == 'bank_refund_instruction' &&
    value['sourceMethod'] == 'bank' &&
    value['sourceOrderId'] == orderId &&
    (request
        ? value['instructionAllowed'] == true && value['status'] == 'pending'
        : value['allowed'] == true);
