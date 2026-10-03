import 'package:fstapp/app_router.gr.dart';

import 'bank_accounts_load_scope.dart';

import 'package:fstapp/components/bank_accounts/views/unit_bank_accounts_screen.dart';
import 'package:fstapp/components/bank_accounts/bank_account_strings.dart';
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
  Widget build(BuildContext context) => const BankAccountsNavigationView();
}

class BankAccountsNavigationView extends StatefulWidget {
  final WidgetBuilder? listBuilder;
  final Future<List<BankAccountModel>> Function(int)? loadAccounts;
  const BankAccountsNavigationView({
    super.key,
    this.listBuilder,
    this.loadAccounts,
  });
  @override
  State<BankAccountsNavigationView> createState() =>
      _BankAccountsNavigationViewState();
}

class _BankAccountsNavigationViewState
    extends State<BankAccountsNavigationView> {
  bool _hadDetail = false;
  int _listRevision = 0;
  Future<List<BankAccountModel>>? _accounts;
  int? _loadedUnitId;
  @override
  Widget build(BuildContext context) => AutoRouter(
        builder: (context, navigator) {
          final unit = UnitAdministrationScope.of(context).unit;
          final hasDetail =
              context.router.current.name == BankAccountDetailRoute.name;
          if (_loadedUnitId != unit.id) {
            _loadedUnitId = unit.id;
            _accounts = null;
          }
          if (_hadDetail && !hasDetail) {
            _listRevision++;
            _accounts = null;
          }
          _hadDetail = hasDetail;
          return BankAccountsLoadScope(
            load: (refresh) {
              if (refresh) _accounts = null;
              return _accounts ??= (widget.loadAccounts ??
                  DbBankAccounts.getBankAccountsForUnit)(
                unit.id!,
              );
            },
            child: Stack(
              fit: StackFit.expand,
              children: [
                KeyedSubtree(
                  key: ValueKey(_listRevision),
                  child: Builder(builder: (context) =>
                      widget.listBuilder?.call(context) ??
                      UnitBankAccountsScreen(unitId: unit.id!))),
                // The empty native list route must not intercept its underlay's
                // edit/add buttons. Detail routes keep their normal pointer handling.
                IgnorePointer(ignoring: !hasDetail, child: navigator),
              ],
            ),
          );
        },
      );
}

// The list stays underneath the routed dialog, including on a direct deep link.
@RoutePage(name: 'UnitBankAccountsListRoute')
class UnitBankAccountsListPage extends StatelessWidget {
  const UnitBankAccountsListPage({super.key});
  @override
  Widget build(BuildContext context) => const SizedBox.shrink();
}

@RoutePage()
class BankAccountDetailPage extends StatefulWidget {
  final String accountId;
  final Future<List<BankAccountModel>> Function(int)? loadAccounts;
  const BankAccountDetailPage({
    super.key,
    @pathParam required this.accountId,
    this.loadAccounts,
  });
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
      final scope = BankAccountsLoadScope.maybeOf(context);
      final accounts = await (widget.loadAccounts != null
          ? widget.loadAccounts!(id)
          : scope?.load(false) ?? DbBankAccounts.getBankAccountsForUnit(id));
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
    RetainedDraftGuard.instance.leaveOwner(
      context,
      () => context.router.replaceAll([UnitBankAccountsListRoute()]),
    );
  }

  @override
  Widget build(BuildContext context) {
    return RoutedBankAccountDialog(
      title: _account?.title ?? BankAccountStrings.bankAccountSettingsTitle,
      onClose: _back,
      child: _failed || _account == null
          ? Center(
              child: _failed
                  ? const Text('Not found or access denied')
                  : const CircularProgressIndicator(),
            )
          : BankAccountSettingsScreen(
              key: ValueKey(widget.accountId),
              unitId: _unitId!,
              account: _account!,
              onUpdated: (account) => setState(() => _account = account),
              readOnly: !_account!.isAdmin,
              routed: true,
            ),
    );
  }
}
