import 'package:fstapp/widgets/app_dialog.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:material_ui/material_ui.dart';
import 'package:fstapp/components/eshop/models/transaction_model.dart';
import 'package:fstapp/components/eshop/db_eshop.dart';
import 'package:fstapp/services/toast_helper.dart';
import 'package:fstapp/services/utilities_all.dart';
import 'package:fstapp/theme_config.dart';
import 'package:fstapp/components/_shared/common_strings.dart';
import 'package:fstapp/components/eshop/orders_strings.dart';

import 'dart:async';

import '../../forms/payment_method_strings.dart';
import '../../bank_accounts/bank_account_strings.dart';
import '../../bank_accounts/views/bank_sync_email_queue.dart';
import '../../../services/exception_handler.dart';

class SearchTransactionsDialog extends StatefulWidget {
  final int? paymentInfoId;
  final int bankAccount;
  final bool readOnly;
  final int? unitId;

  const SearchTransactionsDialog({
    super.key,
    required this.paymentInfoId,
    required this.bankAccount,
    this.readOnly = false,
    this.unitId,
  });

  @override
  _SearchTransactionsDialogState createState() =>
      _SearchTransactionsDialogState();
}

class _SearchTransactionsDialogState extends State<SearchTransactionsDialog> {
  List<TransactionModel> _availableTransactions = [];
  List<TransactionModel> _filteredTransactions = [];
  bool _isLoading = true;
  bool _loadFailed = false;
  bool _reviewing = false;
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

    try {
      final transactions = await DbEshop.getTransactionsForOrderAllAvailable(
        widget.paymentInfoId,
        historyAccountId: widget.readOnly ? widget.bankAccount : null,
        historyUnitId: widget.unitId,
      );
      if (!mounted) return;
      setState(() {
        _availableTransactions = transactions ?? [];
        _filteredTransactions = _availableTransactions;
        _isLoading = false;
        _loadFailed = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _isLoading = false;
        _loadFailed = true;
      });
    }
  }

  void _filterTransactions(String query) {
    if (_debounce?.isActive ?? false) _debounce!.cancel();
    _debounce = Timer(const Duration(milliseconds: 300), () {
      List<TransactionModel> filtered = _availableTransactions.where((
        transaction,
      ) {
        bool matches = false;

        String normalizedQuery = query.toLowerCase();

        if (transaction.messageForRecipient != null &&
            transaction.messageForRecipient!.toLowerCase().contains(
              normalizedQuery,
            )) {
          matches = true;
        }

        if (transaction.counterAccount != null &&
            transaction.counterAccount!.toLowerCase().contains(
              normalizedQuery,
            )) {
          matches = true;
        }

        if (transaction.vs != null &&
            transaction.vs!.toLowerCase().contains(normalizedQuery)) {
          matches = true;
        }

        if (transaction.counterAccountName != null &&
            transaction.counterAccountName!.toLowerCase().contains(
              normalizedQuery,
            )) {
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

  String? _bankReviewLabel(String? decision) => switch (decision) {
    'api_same_movement' => BankAccountStrings.apiDuplicateReviewedSame,
    'api_distinct' => BankAccountStrings.apiDuplicateReviewedDistinct,
    _ => null,
  };

  Future<void> _reviewBankSyncTransaction(
    TransactionModel transaction,
    Map<String, dynamic> review,
  ) async {
    setState(() => _reviewing = true);
    try {
      while (mounted) {
        final candidates = (review['possible_duplicates'] as List)
            .map((item) => Map<String, dynamic>.from(item as Map))
            .toList();
        final decision = await showDialog<({int? existingId})>(
          context: context,
          builder: (context) => AppAlertDialog(
            onClose: () => Navigator.of(context).pop(),
            title: Text(BankAccountStrings.apiDuplicateReviewTitle),
            content: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  BankEmailFacts(
                    facts: {
                      'amount_cents': (transaction.amount! * 100).round(),
                      'currency': transaction.currency,
                      'raw_vs': transaction.vs,
                      'payer_reference': transaction.payerReference,
                      'counter_account': transaction.counterAccount,
                      'bank_code': transaction.bankCode,
                      'sender_name': transaction.counterAccountName,
                      'date': transaction.date?.toIso8601String(),
                    },
                  ),
                  if (transaction.transactionId case final int id) Text('#$id'),
                  if (_bankReviewLabel(review['previous_action'] as String?)
                      case final label?)
                    Text(label),
                  const SizedBox(height: 12),
                  Text(BankAccountStrings.apiDuplicateReviewInstruction),
                  BankEmailPossibleDuplicates(
                    duplicates: candidates,
                    onMatch: (id) =>
                        Navigator.of(context).pop((existingId: id)),
                  ),
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(context).pop(),
                child: Text(CommonStrings.cancel),
              ),
              FilledButton(
                onPressed: () => Navigator.of(context).pop((existingId: null)),
                child: Text(BankAccountStrings.apiDuplicateDistinct),
              ),
            ],
          ),
        );
        if (!mounted || decision == null) return;
        final result = await ExceptionHandler.guard<Map<String, dynamic>>(
          context,
          futureFunction: () => DbEshop.resolveBankSyncApiDuplicate(
            transactionId: transaction.id!,
            paymentInfoId: widget.paymentInfoId!,
            reviewToken: review['review_token'] as String,
            existingTransactionId: decision.existingId,
          ),
        );
        if (!mounted || result == null) return;
        if (result['action'] == 'review_changed') {
          review = result;
          ToastHelper.Show(
            context,
            BankAccountStrings.apiDuplicateReviewChanged,
          );
          continue;
        }
        if (result['action'] == 'api_same_movement' &&
            result['paired_now'] != true) {
          ToastHelper.Show(context, BankAccountStrings.apiDuplicateResolved);
          await _fetchAvailableTransactions();
        } else {
          ToastHelper.Show(context, OrdersStrings.transactionAddedSuccess);
          Navigator.of(context).pop(true);
        }
        return;
      }
    } finally {
      if (mounted) setState(() => _reviewing = false);
    }
  }

  void _selectTransaction(TransactionModel transaction) async {
    if (_reviewing) return;
    if (transaction.bankSyncReview case final review?) {
      await _reviewBankSyncTransaction(transaction, review);
      return;
    }
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AppAlertDialog(
        onClose: () => Navigator.of(context).pop(false),
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
        widget.paymentInfoId!,
      );

      ToastHelper.Show(context, OrdersStrings.transactionAddedSuccess);
      Navigator.of(context).pop(true);
    }
  }

  @override
  Widget build(BuildContext context) {
    return AppAlertDialog(
      onClose: () => Navigator.of(context).pop(),
      title: Text(
        widget.readOnly
            ? PaymentMethodStrings.text('bankHistory')
            : OrdersStrings.searchUnpairedTransactions,
      ),
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
                  : _loadFailed
                  ? Center(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(CommonStrings.unexpectedError),
                          TextButton(
                            onPressed: _fetchAvailableTransactions,
                            child: Text(CommonStrings.retry),
                          ),
                        ],
                      ),
                    )
                  : _filteredTransactions.isEmpty
                  ? Center(
                      child: Text(
                        widget.readOnly
                            ? OrdersStrings.noTransactionsFound
                            : OrdersStrings.noUnpairedTransactionsFound,
                      ),
                    )
                  : SelectionArea(
                      child: ListView.builder(
                        itemCount: _filteredTransactions.length,
                        itemBuilder: (context, index) {
                          final transaction = _filteredTransactions[index];
                          final reviewLabel = _bankReviewLabel(
                            transaction.bankSyncReview?['previous_action']
                                    as String? ??
                                transaction.bankSyncDecision,
                          );
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
                              onTap: widget.readOnly
                                  ? null
                                  : () => _selectTransaction(transaction),
                              borderRadius: BorderRadius.circular(8),
                              child: Padding(
                                padding: const EdgeInsets.all(12.0),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    if (reviewLabel != null)
                                      Text(reviewLabel)
                                    else if (transaction.bankSyncReview != null)
                                      Text(
                                        BankAccountStrings
                                            .apiDuplicateReviewTitle,
                                      ),
                                    Row(
                                      mainAxisAlignment:
                                          MainAxisAlignment.spaceBetween,
                                      children: [
                                        Text(
                                          Utilities.formatPrice(
                                            context,
                                            transaction.amount!,
                                            currencyCode: transaction.currency!,
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
                                              Icon(
                                                Icons.payments,
                                                size: 18,
                                                color: ThemeConfig.grey700(
                                                  context,
                                                ),
                                              ),
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
                                        else if (counterAccountName.isNotEmpty)
                                          Flexible(
                                            child: Text(
                                              counterAccountName,
                                              style: TextStyle(
                                                fontStyle: FontStyle.italic,
                                                color: ThemeConfig.grey600(
                                                  context,
                                                ),
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
                                        context.locale.languageCode,
                                      ).format(transaction.date!),
                                      style: TextStyle(
                                        fontSize: 13,
                                        color: ThemeConfig.grey800(context),
                                      ),
                                    ),
                                    if (transaction
                                        .formattedBankAccount
                                        .isNotEmpty)
                                      Text(
                                        transaction.formattedBankAccount,
                                        style: TextStyle(
                                          fontSize: 12,
                                          color: ThemeConfig.grey600(context),
                                        ),
                                      ),
                                    if (transaction.vs != null &&
                                        transaction.vs!.isNotEmpty)
                                      Text(
                                        '${OrdersStrings.variableSymbol}: ${transaction.vs!}',
                                        style: TextStyle(
                                          fontSize: 12,
                                          color: ThemeConfig.grey600(context),
                                        ),
                                      ),
                                    if (transaction.messageForRecipient !=
                                            null &&
                                        transaction
                                            .messageForRecipient!
                                            .isNotEmpty)
                                      Text(
                                        '${OrdersStrings.message}: ${transaction.messageForRecipient!}',
                                        style: TextStyle(
                                          fontSize: 12,
                                          color: ThemeConfig.grey600(context),
                                        ),
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
      actions: [],
    );
  }
}
