import 'package:flutter/material.dart';
import 'package:fstapp/components/eshop/models/order_model.dart';
import 'package:fstapp/components/bank_accounts/views/bank_sync_warning_button.dart';

class OrderBankSyncWarning extends StatelessWidget {
  final OrderModel order;
  const OrderBankSyncWarning({super.key, required this.order});

  @override
  Widget build(BuildContext context) {
    final warning = order.bankSyncWarning;
    return warning == null
        ? const SizedBox.shrink()
        : BankSyncWarningButton(warning: warning);
  }
}
