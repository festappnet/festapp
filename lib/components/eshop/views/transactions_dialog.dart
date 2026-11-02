import 'package:fstapp/data_services/authorization_capabilities.dart';
import 'package:fstapp/widgets/app_dialog.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:material_ui/material_ui.dart';
import 'package:fstapp/components/eshop/models/payment_info_model.dart';
import 'package:fstapp/components/eshop/models/transaction_model.dart';
import 'package:fstapp/components/eshop/orders_strings.dart';
import 'package:fstapp/data_services/rights_service.dart';
import 'package:fstapp/components/eshop/db_eshop.dart';
import 'package:fstapp/services/dialog_helper.dart';
import 'package:fstapp/services/toast_helper.dart';
import 'package:fstapp/services/utilities_all.dart';
import 'package:fstapp/styles/styles_config.dart';
import 'package:fstapp/theme_config.dart';
import 'package:fstapp/components/eshop/views/search_transactions_dialog.dart';
import 'package:fstapp/components/_shared/common_strings.dart';
import 'package:fstapp/components/bank_accounts/bank_account_strings.dart';

import 'add_cash_payment_dialog.dart';
import '../models/order_model.dart';

class OrderPaymentsContent extends StatefulWidget {
  final Future<void> Function()? onChanged;
  final int orderId;
  final Widget? summary;
  final String? orderSymbol;
  final int? unitId;

  const OrderPaymentsContent({
    super.key,
    required this.orderId,
    this.orderSymbol,
    this.unitId,
    this.onChanged,
    this.summary,
  });

  @override
  _OrderPaymentsContentState createState() => _OrderPaymentsContentState();
}

class _OrderPaymentsContentState extends State<OrderPaymentsContent> {
  List<TransactionModel> _transactions = [];
  PaymentInfoModel? _payment;
  bool _isLoading = true;
  String? _orderState;
  bool get _canEdit =>
      !RightsService.isDemoReadOnly &&
      !_isLoading &&
      _payment?.isStripe != true &&
      OrderModel.canChangePaymentInState(_orderState);

  @override
  void initState() {
    super.initState();
    _fetchTransactions();
  }

  Future<void> _fetchTransactions() async {
    setState(() {
      _isLoading = true;
    });

    final transactionObject = await DbEshop.getTransactionsForOrder(
      widget.orderId,
    );
    if (transactionObject != null) {
      transactionObject.transactions.sort((a, b) => b.date!.compareTo(a.date!));
      setState(() {
        _transactions = transactionObject.transactions;
        _payment = transactionObject.paymentInfo;
        _orderState = transactionObject.orderState;
        _isLoading = false;
      });
    } else {
      setState(() {
        _isLoading = false;
      });
    }
  }

  void _addTransaction() async {
    if (!_canEdit) return;
    var accountIds = RightsService.banksWithCapability(
      AuthorizationCapabilities.bankTransactionsManage,
    );
    if (accountIds.isEmpty) {
      accountIds = [0];
    }

    final result = await showDialog(
      context: context,
      builder: (context) => SearchTransactionsDialog(
        paymentInfoId: _payment!.id!,
        bankAccount: _payment!.bankAccount ?? accountIds.first,
      ),
    );

    if (result == true) {
      await _fetchTransactions();
      await widget.onChanged?.call();
    }
  }

  void _addCashPayment() async {
    if (!_canEdit ||
        !RightsService.hasCapability(
          AuthorizationCapabilities.bankAccountsUnitManage,
        ))
      return;
    final result = await showDialog(
      context: context,
      builder: (context) => AddCashPaymentDialog(
        unitId: widget.unitId ?? RightsService.currentUnit()!.id!,
        currency: _payment!.currencyCode!,
        variableSymbol: _payment!.variableSymbol?.toString() ?? "",
        paymentInfoId: _payment!.id!,
        canManageBankTransactions: _canManageBankTransactions(),
      ),
    );

    if (result == true) {
      await _fetchTransactions();
      await widget.onChanged?.call();
    } else if (result == 'SWITCH_TO_CASHLESS') {
      _addTransaction();
    }
  }

  void _removeTransaction(TransactionModel transaction) async {
    if (!_canEdit) return;
    final isManual = transaction.transactionType == 'manual';
    final confirmMessage = isManual
        ? OrdersStrings.deleteCashTransactionConfirmation
        : OrdersStrings.unlinkTransactionConfirmation;

    final confirm = await DialogHelper.showConfirmationDialog(
      context,
      OrdersStrings.confirmRemoval,
      confirmMessage,
    );

    if (confirm == true) {
      if (isManual) {
        await DbEshop.deleteManualTransactionWithSecurity(
          context,
          transaction.id!,
          _payment!.id!,
        );
      } else {
        await DbEshop.removeTransactionFromPaymentInfoWithSecurity(
          context,
          transaction.id!,
          _payment!.id!,
        );
      }
      ToastHelper.Show(
        context,
        OrdersStrings.removeTransactionSuccess(transaction.toBasicString()),
      );
      await _fetchTransactions();
      await widget.onChanged?.call();
    }
  }

  bool _canManageBankTransactions() {
    if (_payment == null || _payment!.bankAccount == null) {
      return false;
    }
    return RightsService.hasBankCapability(
      _payment!.bankAccount,
      AuthorizationCapabilities.bankTransactionsManage,
    );
  }

  @override
  Widget build(BuildContext context) {
    return _isLoading
        ? SizedBox(
            height: 100,
            child: Center(child: CircularProgressIndicator()),
          )
        : Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              SizedBox(height: 8),
              Wrap(
                alignment: WrapAlignment.end,
                spacing: 10,
                runSpacing: 10,
                children: [
                  ElevatedButton(
                    onPressed:
                        _canEdit &&
                            RightsService.hasCapability(
                              AuthorizationCapabilities.bankAccountsUnitManage,
                            )
                        ? _addCashPayment
                        : null,
                    style: ElevatedButton.styleFrom(
                      padding: EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 12,
                      ),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(8),
                      ),
                    ),
                    child: Text(OrdersStrings.addPayment),
                  ),
                ],
              ),
              if (widget.summary != null) widget.summary!,
              if (_payment != null && _payment!.variableSymbol != null)
                Padding(
                  padding: const EdgeInsets.only(bottom: 10.0),
                  child: SelectionArea(
                    child: Row(
                      children: [
                        Text(
                          "${OrdersStrings.variableSymbol}: ",
                          style: TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 14,
                          ),
                        ),
                        Expanded(
                          child: Text(
                            _payment!.variableSymbol!.toString(),
                            style: TextStyle(fontSize: 14),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              if (_payment != null && _payment!.variableSymbol != null)
                Card(
                  margin: EdgeInsets.only(bottom: 10),
                  elevation: 2,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Padding(
                    padding: const EdgeInsets.all(12.0),
                    child: SelectionArea(
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceAround,
                        children: [
                          Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                OrdersStrings.amount,
                                style: TextStyle(
                                  fontWeight: FontWeight.bold,
                                  fontSize: 14,
                                ),
                              ),
                              SizedBox(height: 4),
                              Text(
                                _payment!.amount != null
                                    ? Utilities.formatPrice(
                                        context,
                                        _payment!.amount!,
                                        currencyCode:
                                            _payment!.currencyCode ?? "N/A",
                                        decimalDigits: 2,
                                      )
                                    : OrdersStrings.notAvailable,
                                style: TextStyle(fontSize: 14),
                              ),
                            ],
                          ),
                          Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                OrdersStrings.paid,
                                style: TextStyle(
                                  fontWeight: FontWeight.bold,
                                  fontSize: 14,
                                ),
                              ),
                              SizedBox(height: 4),
                              Text(
                                _payment!.paid != null
                                    ? Utilities.formatPrice(
                                        context,
                                        _payment!.paid!,
                                        currencyCode:
                                            _payment!.currencyCode ?? "N/A",
                                        decimalDigits: 2,
                                      )
                                    : OrdersStrings.notAvailable,
                                style: TextStyle(fontSize: 14),
                              ),
                            ],
                          ),
                          Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                OrdersStrings.returned,
                                style: TextStyle(
                                  fontWeight: FontWeight.bold,
                                  fontSize: 14,
                                ),
                              ),
                              SizedBox(height: 4),
                              Text(
                                _payment!.returned != null
                                    ? Utilities.formatPrice(
                                        context,
                                        _payment!.returned!,
                                        currencyCode:
                                            _payment!.currencyCode ?? "N/A",
                                        decimalDigits: 2,
                                      )
                                    : OrdersStrings.notAvailable,
                                style: TextStyle(fontSize: 14),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              if (_transactions.isEmpty)
                Text(OrdersStrings.noTransactionsFound)
              else
                Padding(
                  padding: EdgeInsets.zero,
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(),
                    child: SizedBox(
                      width: StylesConfig.formMaxWidth,
                      child: SelectionArea(
                        child: ListView.builder(
                          shrinkWrap: true,
                          physics: const NeverScrollableScrollPhysics(),
                          itemCount: _transactions.length,
                          itemBuilder: (context, index) {
                            final transaction = _transactions[index];
                            final counterAccountName =
                                transaction.counterAccountName ??
                                transaction.performedBy ??
                                transaction.counterAccount ??
                                OrdersStrings.notAvailable;

                            return Card(
                              margin: EdgeInsets.symmetric(vertical: 5),
                              elevation: 2,
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: Padding(
                                padding: const EdgeInsets.all(12.0),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Row(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        Expanded(
                                          child: Column(
                                            crossAxisAlignment:
                                                CrossAxisAlignment.start,
                                            children: [
                                              Row(
                                                mainAxisAlignment:
                                                    MainAxisAlignment
                                                        .spaceBetween,
                                                children: [
                                                  Text(
                                                    Utilities.formatPrice(
                                                      context,
                                                      transaction.amount!,
                                                      currencyCode:
                                                          transaction
                                                              .currency ??
                                                          "N/A",
                                                      decimalDigits: 2,
                                                    ),
                                                    style: TextStyle(
                                                      fontWeight:
                                                          FontWeight.bold,
                                                      fontSize: 16,
                                                    ),
                                                  ),
                                                  if (transaction
                                                          .transactionType ==
                                                      'manual')
                                                    Row(
                                                      children: [
                                                        Icon(
                                                          Icons.payments,
                                                          size: 18,
                                                          color:
                                                              Colors.grey[700],
                                                        ),
                                                        SizedBox(width: 8),
                                                        Text(
                                                          OrdersStrings
                                                              .transactionTypeCash,
                                                          style: TextStyle(
                                                            fontWeight:
                                                                FontWeight.bold,
                                                            fontSize: 15,
                                                          ),
                                                        ),
                                                      ],
                                                    )
                                                  else if (counterAccountName
                                                      .isNotEmpty)
                                                    Text(
                                                      counterAccountName,
                                                      style: TextStyle(
                                                        fontStyle:
                                                            FontStyle.italic,
                                                        color:
                                                            ThemeConfig.grey600(
                                                              context,
                                                            ),
                                                        fontSize: 14,
                                                      ),
                                                    ),
                                                ],
                                              ),
                                              SizedBox(height: 6),
                                            ],
                                          ),
                                        ),
                                        if (_canManageBankTransactions())
                                          IconButton(
                                            icon: Icon(Icons.delete),
                                            tooltip: OrdersStrings
                                                .removeTransactionTooltip,
                                            onPressed: !_canEdit
                                                ? null
                                                : () => _removeTransaction(
                                                    transaction,
                                                  ),
                                          ),
                                      ],
                                    ),
                                    _buildInfoRow(
                                      title: OrdersStrings.date,
                                      value: transaction.date != null
                                          ? DateFormat.yMMMd(
                                              context.locale.languageCode,
                                            ).format(transaction.date!)
                                          : OrdersStrings.notAvailable,
                                    ),
                                    SizedBox(height: 5),
                                    _buildInfoRow(
                                      title: OrdersStrings.amount,
                                      value: transaction.amount != null
                                          ? Utilities.formatPrice(
                                              context,
                                              transaction.amount!,
                                              currencyCode:
                                                  transaction.currency ?? "N/A",
                                              decimalDigits: 2,
                                            )
                                          : OrdersStrings.notAvailable,
                                    ),
                                    SizedBox(height: 5),
                                    if (transaction.transactionType !=
                                        'manual') ...[
                                      _buildInfoRow(
                                        title: BankAccountStrings.bankAccount,
                                        value:
                                            transaction
                                                .formattedBankAccount
                                                .isNotEmpty
                                            ? transaction.formattedBankAccount
                                            : OrdersStrings.notAvailable,
                                      ),
                                      SizedBox(height: 5),
                                    ],
                                    if (transaction.transactionType !=
                                            'manual' &&
                                        transaction.vs != null &&
                                        transaction.vs!.isNotEmpty)
                                      _buildInfoRow(
                                        title: OrdersStrings.variableSymbol,
                                        value: transaction.vs!,
                                      ),
                                    if (transaction.transactionType !=
                                            'manual' &&
                                        transaction.vs != null &&
                                        transaction.vs!.isNotEmpty)
                                      SizedBox(height: 5),
                                    if (transaction.transactionType ==
                                            'manual' &&
                                        transaction.comment != null &&
                                        transaction.comment!.isNotEmpty)
                                      _buildInfoRow(
                                        title: CommonStrings.note,
                                        value: transaction.comment!,
                                      ),
                                    if (transaction.messageForRecipient !=
                                            null &&
                                        transaction
                                            .messageForRecipient!
                                            .isNotEmpty)
                                      _buildInfoRow(
                                        title:
                                            OrdersStrings.messageForRecipient,
                                        value: transaction.messageForRecipient!,
                                      ),
                                    if (transaction.transactionType ==
                                            'manual' &&
                                        transaction.createdByName != null)
                                      _buildInfoRow(
                                        title: OrdersStrings.acceptedBy,
                                        value: transaction.createdByName!,
                                      ),
                                  ],
                                ),
                              ),
                            );
                          },
                        ),
                      ),
                    ),
                  ),
                ),
            ],
          );
  }

  Widget _buildInfoRow({
    required String title,
    required String value,
    bool isBold = false,
  }) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          flex: 3,
          child: Text(
            '$title:',
            style: TextStyle(
              fontWeight: isBold ? FontWeight.bold : FontWeight.normal,
            ),
          ),
        ),
        Expanded(flex: 5, child: Text(value)),
      ],
    );
  }
}

class TransactionsDialog extends StatelessWidget {
  const TransactionsDialog({
    super.key,
    required this.orderId,
    this.orderSymbol,
    this.unitId,
  });
  final int orderId;
  final String? orderSymbol;
  final int? unitId;
  @override
  Widget build(BuildContext context) => AppAlertDialog(
    title: Text(OrdersStrings.transactionsForOrder(orderSymbol ?? '')),
    content: SizedBox(
      width: 600,
      child: SingleChildScrollView(
        child: OrderPaymentsContent(
          orderId: orderId,
          orderSymbol: orderSymbol,
          unitId: unitId,
        ),
      ),
    ),
  );
}
