import 'package:flutter/widgets.dart';

import '../bank_account_model.dart';

/// One unit-list request shared by the underlay and its routed account dialog.
class BankAccountsLoadScope extends InheritedWidget {
  final Future<List<BankAccountModel>> Function(bool refresh) load;
  const BankAccountsLoadScope({
    super.key,
    required this.load,
    required super.child,
  });
  static BankAccountsLoadScope? maybeOf(BuildContext context) =>
      context.getInheritedWidgetOfExactType<BankAccountsLoadScope>();
  @override
  bool updateShouldNotify(BankAccountsLoadScope oldWidget) => false;
}
