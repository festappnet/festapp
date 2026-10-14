import 'package:fstapp/services/app_logger.dart';
import 'unit_bank_account_card.dart';
import 'package:fstapp/widgets/app_dialog.dart';
import 'bank_accounts_load_scope.dart';
import 'package:auto_route/auto_route.dart';
import 'package:flutter/material.dart';
import 'package:fstapp/app_router.gr.dart';
import 'dart:convert';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:fstapp/components/bank_accounts/bank_account_model.dart';
import 'package:fstapp/components/bank_accounts/db_bank_accounts.dart';
import 'package:fstapp/components/bank_accounts/views/bank_account_settings_screen.dart';
import 'package:fstapp/components/bank_accounts/bank_account_strings.dart';
import 'package:fstapp/theme_config.dart';
import 'package:fstapp/components/html/html_view.dart';
import 'package:fstapp/app_config.dart';
import 'package:fstapp/components/_shared/common_strings.dart';
import 'package:fstapp/components/users/db_users.dart';

class UnitBankAccountsScreen extends StatefulWidget {
  final int unitId;

  const UnitBankAccountsScreen(
      {super.key, @PathParam.inherit('id') required this.unitId});

  @override
  State<UnitBankAccountsScreen> createState() => _UnitBankAccountsScreenState();
}

class _UnitBankAccountsScreenState extends State<UnitBankAccountsScreen> {
  List<BankAccountModel> _unitAccounts = [];

  bool _isLoading = true;
  bool _hasLoaded = false;
  int? _organizationId;

  @override
  void initState() {
    super.initState();
    DbBankAccounts.connectionChanges.addListener(_bankConnectionChanged);
    _loadData();
  }

  bool _refreshingConnections = false;

  void _bankConnectionChanged() {
    final id = DbBankAccounts.connectionChanges.value.accountId;
    if (_unitAccounts.any((account) => account.id == id)) {
      _refreshConnections();
    }
  }

  Future<void> _refreshConnections() async {
    if (_refreshingConnections || !mounted) return;
    _refreshingConnections = true;
    try {
      final accounts =
          await (BankAccountsLoadScope.maybeOf(context)?.load(true) ??
              DbBankAccounts.getBankAccountsForUnit(widget.unitId));
      if (mounted) setState(() => _unitAccounts = accounts);
    } catch (error) {
      AppLogger.error('Could not refresh bank account cards: $error');
    } finally {
      _refreshingConnections = false;
    }
  }

  @override
  void dispose() {
    DbBankAccounts.connectionChanges.removeListener(_bankConnectionChanged);
    super.dispose();
  }

  void _showError(String message) {
    showDialog(
      context: context,
      builder: (context) => AppAlertDialog(
        title: const Text('Error'),
        content: SelectableText(message),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('OK'),
          ),
        ],
      ),
    );
  }

  Future<void> _loadData() async {
    setState(() => _isLoading = true);
    try {
      // Share the initial list request with a routed detail; mutations refresh.
      final accounts =
          BankAccountsLoadScope.maybeOf(context)?.load(_hasLoaded) ??
              DbBankAccounts.getBankAccountsForUnit(widget.unitId);
      _hasLoaded = true;
      _unitAccounts = await accounts;
      // Get Organization ID (if admin)
      final orgData = await DbUsers.getCurrentOrganization();
      _organizationId = orgData?.id;

      if (!mounted) return;
      setState(() {
        _isLoading = false;
      });
    } catch (e) {
      if (mounted) {
        setState(() => _isLoading = false);
        _showError('Error loading accounts: $e');
      }
    }
  }

  Future<List<BankAccountModel>> _loadAvailableAccounts() async {
    final organizationAccounts = _organizationId == null
        ? <BankAccountModel>[]
        : await DbBankAccounts.getBankAccountsForOrganization(_organizationId!);
    final myAccounts = await DbBankAccounts.getMyAdminBankAccounts();
    final linkedIds = _unitAccounts.map((account) => account.id).toSet();
    final available = <int, BankAccountModel>{};
    for (final account in [...organizationAccounts, ...myAccounts]) {
      if (!linkedIds.contains(account.id)) {
        available.putIfAbsent(account.id, () => account);
      }
    }
    return available.values.toList();
  }

  Future<void> _addOrEditAccount([BankAccountModel? account]) async {
    // If editing existing, we check if it is org account

    if (account == null) {
      // Creation Flow
      // Create new account logic
      // However, we need to link it to the current Unit too? Ideally yes.

      BankAccountModel? selectedAccount;
      bool createNew = true;

      Future<List<BankAccountModel>>? availableAccounts;
      final choice = await showDialog<String>(
        context: context,
        builder: (context) => StatefulBuilder(
          builder: (context, updateDialog) {
            availableAccounts ??= _loadAvailableAccounts();
            return FutureBuilder<List<BankAccountModel>>(
              future: availableAccounts,
              builder: (context, snapshot) => AppSimpleDialog(
                title: Text(BankAccountStrings.addBankAccount),
                children: [
                  TextButton(
                    onPressed: () => Navigator.pop(context, 'new'),
                    child: Text(BankAccountStrings.createNewAccount),
                  ),
                  TextButton(
                    onPressed: snapshot.hasData && snapshot.data!.isNotEmpty
                        ? () => Navigator.pop(context, 'link')
                        : null,
                    child: Text(BankAccountStrings.linkExistingAccount),
                  ),
                  if (snapshot.connectionState == ConnectionState.waiting)
                    Padding(
                      padding: const EdgeInsets.all(16),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          const SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          ),
                          const SizedBox(width: 8),
                          Text(CommonStrings.loading),
                        ],
                      ),
                    ),
                  if (snapshot.hasError) ...[
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      child: Text(CommonStrings.unexpectedError),
                    ),
                    TextButton(
                      onPressed: () => updateDialog(() {
                        availableAccounts = null;
                      }),
                      child: Text(CommonStrings.retry),
                    ),
                  ],
                ],
              ),
            );
          },
        ),
      );

      if (choice == null || !mounted) return;
      createNew = choice == 'new';

      if (!createNew) {
        final accounts = await availableAccounts!;
        if (!mounted) return;

        selectedAccount = await showDialog<BankAccountModel>(
          context: context,
          builder: (context) => AppSimpleDialog(
            title: Text(BankAccountStrings.selectAccount),
            children: accounts
                .map((a) => SimpleDialogOption(
                      onPressed: () => Navigator.pop(context, a),
                      child: Padding(
                        padding: const EdgeInsets.all(8.0),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(a.title ?? BankAccountStrings.untitled,
                                style: const TextStyle(
                                    fontWeight: FontWeight.bold)),
                            Text(
                              '${a.accountNumber}',
                              style: Theme.of(context).textTheme.bodySmall,
                            ),
                          ],
                        ),
                      ),
                    ))
                .toList(),
          ),
        );
        if (selectedAccount == null) return;
      } else {
        // Create New

        selectedAccount = await showDialog<BankAccountModel>(
          context: context,
          builder: (context) => BankAccountSettingsScreen(
            unitId: widget.unitId,
            organizationId: _organizationId, // Passing it here
            account: BankAccountModel(id: 0, type: 'FIO'),
            isDialog: true,
          ),
        );
      }

      if (selectedAccount != null) {
        setState(() => _isLoading = true);
        try {
          // Link it to the unit
          int bankAccountId = selectedAccount.id;
          int priority =
              _unitAccounts.isEmpty ? 0 : _unitAccounts.last.priority + 1;
          await DbBankAccounts.linkBankAccountToUnit(
              widget.unitId, bankAccountId, priority);

          await _loadData();
        } catch (e) {
          if (mounted) _showError('$e');
        } finally {
          if (mounted) setState(() => _isLoading = false);
        }
      }
    } else {
      await context.router
          .push(BankAccountDetailRoute(accountId: account.id.toString()));
      // The navigation owner refreshes the underlay once when detail closes.
    }
  }

  Future<void> _unlinkAccount(BankAccountModel account) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AppAlertDialog(
        title: Text(BankAccountStrings.unlinkConfirmationTitle),
        content: Text(BankAccountStrings.unlinkConfirmationMessage),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: Text(BankAccountStrings.cancel)),
          TextButton(
              style: TextButton.styleFrom(
                  foregroundColor: Theme.of(context).colorScheme.error),
              onPressed: () => Navigator.pop(context, true),
              child: Text(BankAccountStrings.unlink)),
        ],
      ),
    );

    if (confirm == true) {
      await _performUnlink(account, false);
    }
  }

  Future<void> _performUnlink(BankAccountModel account, bool hard) async {
    setState(() => _isLoading = true);
    try {
      await DbBankAccounts.linkBankAccountToUnit(
          widget.unitId, account.id, null,
          hard: hard);
      await _loadData();
    } catch (e) {
      if (mounted) setState(() => _isLoading = false);

      if (e is LinkDependencyException) {
        if (mounted) _showDependencyWarning(account, e.conflicts);
        return;
      }

      // Fallback for PostgrestException if DB layer rethrows raw error
      if (e is PostgrestException &&
          e.message.contains('LINK_DEPENDENCY_ERROR')) {
        try {
          final msg = e.message;
          final start = msg.indexOf('{');
          final end = msg.lastIndexOf('}');
          if (start != -1 && end != -1) {
            final jsonStr = msg.substring(start, end + 1);
            final data = json.decode(jsonStr);
            if (data['code'] == 'LINK_DEPENDENCY_ERROR') {
              if (mounted) _showDependencyWarning(account, data['conflicts']);
              return;
            }
          }
        } catch (_) {
          // ignore fallbacks failure, will show generic error
        }
      }

      if (mounted) {
        _showError('Error removing account: $e');
      }
    }
  }

  void _showDependencyWarning(
      BankAccountModel account, List<dynamic> conflicts) {
    showDialog(
      context: context,
      builder: (context) => AppAlertDialog(
        title: Text(BankAccountStrings.unlinkDependencyWarningTitle),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SelectableText(BankAccountStrings.unlinkDependencyMessage),
            const SizedBox(height: 10),
            SelectableText(
              BankAccountStrings.unlinkDependencyConsequence,
              style: TextStyle(
                  fontWeight: FontWeight.bold,
                  color: ThemeConfig.redColor(context)),
            ),
            const SizedBox(height: 10),
            Container(
              constraints: const BoxConstraints(maxHeight: 200),
              child: SingleChildScrollView(
                child: HtmlView(
                  isSelectable: true,
                  html: () {
                    // Group conflicts by Occasion
                    final Map<String, List<dynamic>> grouped = {};
                    for (var c in conflicts) {
                      final occasion = c['occasion'] ?? 'Unknown Occasion';
                      grouped.putIfAbsent(occasion, () => []).add(c);
                    }

                    // Build HTML
                    String html = "";
                    grouped.forEach((occasion, items) {
                      html += "<b>$occasion</b><ul>";
                      for (var c in items) {
                        final title = c['form'] ?? c['link'] ?? 'Unknown Form';
                        final currency = c['currency'];
                        final link = c['link'];
                        final fullUrl = link != null
                            ? "${AppConfig.webLink}/form/$link"
                            : null;

                        String content = "$title ($currency)";
                        if (fullUrl != null) {
                          content += "<br><a href=\"$fullUrl\">$fullUrl</a>";
                        }
                        html += "<li>$content</li>";
                      }
                      html += "</ul>";
                    });
                    return html;
                  }(),
                  fontSize: 13,
                ),
              ),
            )
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text(BankAccountStrings.cancel),
          ),
          TextButton(
            style: TextButton.styleFrom(
                foregroundColor: Theme.of(context).colorScheme.error),
            onPressed: () {
              Navigator.pop(context);
              _performUnlink(account, true);
            },
            child: Text(BankAccountStrings.unlinkAnyway),
          ),
        ],
      ),
    );
  }

  Future<void> _onReorder(int oldIndex, int newIndex) async {
    if (oldIndex < newIndex) {
      newIndex -= 1;
    }
    final item = _unitAccounts.removeAt(oldIndex);
    _unitAccounts.insert(newIndex, item);
    setState(() {}); // Update UI immediately

    // Update priorities in DB
    try {
      for (int i = 0; i < _unitAccounts.length; i++) {
        await DbBankAccounts.linkBankAccountToUnit(
            widget.unitId, _unitAccounts[i].id, i);
      }
    } catch (e) {
      _showError('Error saving order: $e');
      _loadData(); // Revert on error
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(BankAccountStrings.bankAccountsTitle),
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 800),
                child: Column(
                  children: [
                    Padding(
                      padding: const EdgeInsets.all(16.0),
                      child: Text(
                        BankAccountStrings.description,
                        style: Theme.of(context).textTheme.bodyMedium,
                        textAlign: TextAlign.center,
                      ),
                    ),
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 16.0),
                      child: Align(
                        alignment: Alignment.centerRight,
                        child: FilledButton.icon(
                          onPressed: () => _addOrEditAccount(),
                          icon: const Icon(Icons.add),
                          label: Text(BankAccountStrings.addBankAccount),
                        ),
                      ),
                    ),
                    Expanded(
                      child: ReorderableListView.builder(
                        buildDefaultDragHandles: false,
                        itemCount: _unitAccounts.length,
                        onReorder: _onReorder,
                        itemBuilder: (context, index) {
                          final account = _unitAccounts[index];
                          final higherPriorityCurrencies = _unitAccounts
                              .take(index)
                              .expand((account) => account.supportedCurrencies)
                              .toSet();
                          return UnitBankAccountCard(
                            key: ValueKey(account.id),
                            account: account,
                            primaryCurrencies: account.supportedCurrencies
                                .where((currency) => !higherPriorityCurrencies
                                    .contains(currency))
                                .toSet(),
                            index: index,
                            onOpen: () => _addOrEditAccount(account),
                            onUnlink: () => _unlinkAccount(account),
                          );
                        },
                      ),
                    ),
                  ],
                ),
              ),
            ),
    );
  }
}
