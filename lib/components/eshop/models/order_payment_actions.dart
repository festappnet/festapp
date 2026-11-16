/// Authorized actions from the order transaction reader. No client policy rules.
class OrderPaymentActions {
  const OrderPaymentActions({
    this.canAddCash = false,
    this.canConfigureBank = false,
    this.showBankSetup = false,
    this.showBankAccess = false,
    this.bankState = 'restricted',
    this.unitId,
    this.pairingAccountId,
    this.removableTransactionIds = const {},
  });
  final bool canAddCash, canConfigureBank, showBankSetup, showBankAccess;
  final String bankState;
  final int? pairingAccountId, unitId;
  final Set<int> removableTransactionIds;
  factory OrderPaymentActions.fromJson(Map value) => OrderPaymentActions(
    canAddCash: value['canAddCash'] == true,
    canConfigureBank: value['canConfigureBank'] == true,
    showBankSetup: value['showBankSetup'] == true,
    showBankAccess: value['showBankAccess'] == true,
    bankState: value['bankState'] as String? ?? 'restricted',
    pairingAccountId: value['pairingAccountId'] as int?,
    unitId: value['unitId'] as int?,
    removableTransactionIds: Set.unmodifiable(
      (value['removableTransactionIds'] as List? ?? const []).whereType<int>(),
    ),
  );
}

