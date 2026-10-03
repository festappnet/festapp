import 'package:fstapp/app_router.gr.dart';
import 'package:fstapp/components/navigation/retained_draft_guard.dart';
import 'package:auto_route/auto_route.dart';
import 'package:flutter/material.dart';
import 'package:fstapp/components/bank_accounts/bank_account_model.dart';
import 'package:fstapp/components/bank_accounts/db_bank_accounts.dart';
import 'package:fstapp/components/bank_accounts/views/bank_account_settings_screen.dart';
import 'package:fstapp/components/unit/views/unit_admin_page.dart';

@RoutePage()
class UnitBankAccountsNavigationPage extends StatelessWidget {
  const UnitBankAccountsNavigationPage({super.key});
  @override
  Widget build(BuildContext context) => const AutoRouter();
}

@RoutePage()
class BankAccountDetailPage extends StatefulWidget {
  final String accountId;
  final Future<List<BankAccountModel>> Function(int)? loadAccounts;
  const BankAccountDetailPage(
      {super.key, @pathParam required this.accountId, this.loadAccounts});
  @override
  State<BankAccountDetailPage> createState() => _BankAccountDetailPageState();
}

class _BankAccountDetailPageState extends State<BankAccountDetailPage> {
  BankAccountModel? _account;
  bool _failed = false;
  int _generation = 0;
  int? _unitId;
  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final id = UnitAdministrationScope.of(context).unit.id!;
    if (_unitId != id) {
      _unitId = id;
      _load();
    }
  }

  @override
  void didUpdateWidget(BankAccountDetailPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.accountId != widget.accountId) {
      _account = null;
      _failed = false;
      _load();
    }
  }

  Future<void> _load() async {
    final generation = ++_generation;
    final id = _unitId!;
    if (int.tryParse(widget.accountId) == null) {
      setState(() => _failed = true);
      return;
    }
    try {
      final accounts = await (widget.loadAccounts ??
          DbBankAccounts.getBankAccountsForUnit)(id);
      if (!mounted || generation != _generation) return;
      BankAccountModel? account;
      for (final candidate in accounts) {
        if (candidate.id == int.tryParse(widget.accountId)) account = candidate;
      }
      setState(() {
        // The loaded route scope owns this unit. Global rights may temporarily
        // change while the enclosing boundary refreshes; it gates visibility.
        _account = account;
        _failed = _account == null;
      });
    } catch (_) {
      if (mounted && generation == _generation) setState(() => _failed = true);
    }
  }

  void _back() {
    RetainedDraftGuard.instance.leaveOwner(context,
        () => context.router.replaceAll([UnitBankAccountsListRoute()]));
  }

  @override
  Widget build(BuildContext context) {
    if (_failed)
      return Scaffold(
        appBar: AppBar(
            leading: IconButton(
                icon: const Icon(Icons.arrow_back), onPressed: _back)),
        body: const Center(child: Text('Not found or access denied')),
      );
    if (_account == null)
      return const Center(child: CircularProgressIndicator());
    return BankAccountSettingsScreen(
        key: ValueKey(widget.accountId),
        unitId: _unitId!,
        account: _account!,
        readOnly: !_account!.isAdmin,
        routed: true);
  }
}
