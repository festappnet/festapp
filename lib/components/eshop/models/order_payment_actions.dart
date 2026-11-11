/// Authorized actions from the order transaction reader. No client policy rules.
class OrderPaymentActions {
  const OrderPaymentActions({
    this.canAddCash = false,
    this.canConfigureBank = false,
    this.bankState = 'restricted',
    this.unitId,
    this.pairingAccountId,
    this.historyAccounts = const [],
    this.removableTransactionIds = const {},
  });
  final bool canAddCash, canConfigureBank;
  final String bankState;
  final int? pairingAccountId, unitId;
  final List<PaymentHistoryAccount> historyAccounts;
  final Set<int> removableTransactionIds;
  factory OrderPaymentActions.fromJson(Map value) => OrderPaymentActions(
    canAddCash: value['canAddCash'] == true,
    canConfigureBank: value['canConfigureBank'] == true,
    bankState: value['bankState'] as String? ?? 'restricted',
    pairingAccountId: value['pairingAccountId'] as int?,
    unitId: value['unitId'] as int?,
    historyAccounts: List.unmodifiable(
      (value['historyAccounts'] as List? ?? const []).whereType<Map>().map(
        (v) =>
            PaymentHistoryAccount(v['id'] as int, v['title'] as String? ?? ''),
      ),
    ),
    removableTransactionIds: Set.unmodifiable(
      (value['removableTransactionIds'] as List? ?? const []).whereType<int>(),
    ),
  );
}

class PaymentHistoryAccount {
  const PaymentHistoryAccount(this.id, this.title);
  final int id;
  final String title;
}
