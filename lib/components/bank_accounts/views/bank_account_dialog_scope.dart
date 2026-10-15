import 'package:flutter/material.dart';

/// Routes nested pickers above the URL-backed bank account modal.
class BankAccountDialogScope extends InheritedWidget {
  final BuildContext dialogContext;
  const BankAccountDialogScope({
    super.key,
    required this.dialogContext,
    required super.child,
  });

  static BuildContext contextOf(BuildContext context) =>
      context
          .dependOnInheritedWidgetOfExactType<BankAccountDialogScope>()
          ?.dialogContext ??
      context;

  @override
  bool updateShouldNotify(BankAccountDialogScope oldWidget) =>
      dialogContext != oldWidget.dialogContext;
}
