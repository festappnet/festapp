import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:fstapp/components/eshop/models/transaction_model.dart';
import 'package:fstapp/components/eshop/db_eshop.dart';
import 'package:fstapp/services/toast_helper.dart';
import 'package:fstapp/services/utilities_all.dart';
import 'package:fstapp/theme_config.dart';
import 'package:fstapp/components/_shared/common_strings.dart';
import 'package:fstapp/components/eshop/orders_strings.dart';
import 'dart:async';

class SearchTransactionsDialog extends StatefulWidget {
  final int paymentInfoId;
  final int bankAccount;

  const SearchTransactionsDialog({
    super.key,
    required this.paymentInfoId,
    required this.bankAccount,
  });

  @override
  _SearchTransactionsDialogState createState() =>
      _SearchTransactionsDialogState();
}

class _SearchTransactionsDialogState extends State<SearchTransactionsDialog> {
  List<TransactionModel> _availableTransactions = [];
  List<TransactionModel> _filteredTransactions = [];
  bool _isLoading = true;
  Timer? _debounce;
  final _searchController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _fetchAvailableTransactions();
    _searchController.addListener(_onSearchChanged);
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _searchController.dispose();
    super.dispose();
  }

  void _onSearchChanged() {
    _filterTransactions(_searchController.text);
  }

  Future<void> _fetchAvailableTransactions() async {
    setState(() {
      _isLoading = true;
    });

    final transactions =
        await DbEshop.getTransactionsForOrderAllAvailable(widget.paymentInfoId);

    if (transactions != null) {
      if (mounted) {
        setState(() {
          _availableTransactions = transactions;
          _filteredTransactions = transactions;
          _isLoading = false;
        });
      }
    } else {
      if (mounted) {
        setState(() {
          _availableTransactions = [];
          _filteredTransactions = [];
          _isLoading = false;
        });
      }
    }
  }

  void _filterTransactions(String query) {
    if (_debounce?.isActive ?? false) _debounce!.cancel();
    _debounce = Timer(const Duration(milliseconds: 300), () {
      List<TransactionModel> filtered =
          _availableTransactions.where((transaction) {
        bool matches = false;

        String normalizedQuery = query.toLowerCase();

        if (transaction.messageForRecipient != null &&
            transaction.messageForRecipient!
                .toLowerCase()
                .contains(normalizedQuery)) {
          matches = true;
        }

        if (transaction.counterAccount != null &&
            transaction.counterAccount!
                .toLowerCase()
                .contains(normalizedQuery)) {
          matches = true;
        }

        if (transaction.vs != null &&
            transaction.vs!.toLowerCase().contains(normalizedQuery)) {
          matches = true;
        }

        if (transaction.counterAccountName != null &&
            transaction.counterAccountName!
                .toLowerCase()
                .contains(normalizedQuery)) {
          matches = true;
        }

        double? queryAmount = double.tryParse(query);
        if (queryAmount != null) {
          const double epsilon = 0.01;
          if ((transaction.amount! - queryAmount).abs() < epsilon) {
            matches = true;
          }
        }

        return matches;
      }).toList();

      if (mounted) {
        setState(() {
          _filteredTransactions = filtered;
        });
      }
    });
  }

  void _selectTransaction(TransactionModel transaction) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(CommonStrings.confirm),
        content: Text(OrdersStrings.addTransactionConfirmation),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: Text(CommonStrings.cancel),
          ),
          ElevatedButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: Text(CommonStrings.add),
          ),
        ],
      ),
    );

    if (confirm != true) return;

    if (mounted) {
      await DbEshop.addTransactionToPaymentInfoWithSecurity(
        context,
        transaction.id!,
        widget.paymentInfoId,
      );

      ToastHelper.Show(context, OrdersStrings.transactionAddedSuccess);
      Navigator.of(context).pop(true);
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(OrdersStrings.searchUnpairedTransactions),
      content: SizedBox(
        width: 400,
        height: 500,
        child: Column(
          children: [
            TextField(
              controller: _searchController,
              decoration: InputDecoration(
                labelText: CommonStrings.search,
                hintText: OrdersStrings.searchTransactionsHint,
                prefixIcon: Icon(Icons.search),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                ),
                isDense: true,
              ),
            ),
            SizedBox(height: 10),
            Expanded(
              child: _isLoading
                  ? Center(child: CircularProgressIndicator())
                  : _filteredTransactions.isEmpty
                      ? Center(child: Text(OrdersStrings.noUnpairedTransactionsFound))
                      : SelectionArea(
                          child: ListView.builder(
                            itemCount: _filteredTransactions.length,
                            itemBuilder: (context, index) {
                              final transaction = _filteredTransactions[index];
                              final counterAccountName =
                                  transaction.counterAccountName ??
                                      transaction.performedBy ??
                                      OrdersStrings.notAvailable;

                              return Card(
                                margin: EdgeInsets.symmetric(vertical: 4),
                                elevation: 1,
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(8),
                                ),
                                child: InkWell(
                                  onTap: () => _selectTransaction(transaction),
                                  borderRadius: BorderRadius.circular(8),
                                  child: Padding(
                                    padding: const EdgeInsets.all(12.0),
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        Row(
                                          mainAxisAlignment:
                                              MainAxisAlignment.spaceBetween,
                                          children: [
                                            Text(
                                              Utilities.formatPrice(
                                                context,
                                                transaction.amount!,
                                                currencyCode:
                                                    transaction.currency!,
                                                decimalDigits: 2,
                                              ),
                                              style: TextStyle(
                                                fontWeight: FontWeight.bold,
                                                fontSize: 16,
                                              ),
                                            ),
                                            if (transaction.transactionType ==
                                                'manual')
                                              Row(
                                                children: [
                                                  Icon(Icons.payments,
                                                      size: 18,
                                                      color: ThemeConfig.grey700(
                                                          context)),
                                                  SizedBox(width: 8),
                                                  Text(
                                                    OrdersStrings
                                                        .transactionTypeCash,
                                                    style: TextStyle(
                                                      fontWeight: FontWeight.bold,
                                                      fontSize: 15,
                                                    ),
                                                  ),
                                                ],
                                              )
                                            else if (counterAccountName
                                                .isNotEmpty)
                                              Flexible(
                                                child: Text(
                                                  counterAccountName,
                                                  style: TextStyle(
                                                    fontStyle: FontStyle.italic,
                                                    color: ThemeConfig.grey600(
                                                        context),
                                                    fontSize: 14,
                                                  ),
                                                  overflow: TextOverflow.ellipsis,
                                                ),
                                              ),
                                          ],
                                        ),
                                        SizedBox(height: 4),
                                        Text(
                                          DateFormat.yMMMd(
                                                  context.locale.languageCode)
                                              .format(transaction.date!),
                                          style: TextStyle(
                                              fontSize: 13,
                                              color:
                                                  ThemeConfig.grey800(context)),
                                        ),
                                        if (transaction.formattedBankAccount.isNotEmpty)
                                          Text(
                                            transaction.formattedBankAccount,
                                            style: TextStyle(
                                                fontSize: 12,
                                                color:
                                                    ThemeConfig.grey600(context)),
                                          ),
                                        if (transaction.vs != null &&
                                            transaction.vs!.isNotEmpty)
                                          Text(
                                            '${OrdersStrings.variableSymbol}: ${transaction.vs!}',
                                            style: TextStyle(
                                                fontSize: 12,
                                                color:
                                                    ThemeConfig.grey600(context)),
                                          ),
                                        if (transaction.messageForRecipient !=
                                                null &&
                                            transaction
                                                .messageForRecipient!.isNotEmpty)
                                          Text(
                                            '${OrdersStrings.message}: ${transaction.messageForRecipient!}',
                                            style: TextStyle(
                                                fontSize: 12,
                                                color:
                                                    ThemeConfig.grey600(context)),
                                            maxLines: 2,
                                            overflow: TextOverflow.ellipsis,
                                          ),
                                      ],
                                    ),
                                  ),
                                ),
                              );
                            },
                          ),
                        ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text(CommonStrings.close),
        ),
      ],
    );
  }
}
