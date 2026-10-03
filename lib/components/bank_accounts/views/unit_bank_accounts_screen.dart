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
import 'package:fstapp/components/_shared/drag_handle_dots.dart';
import 'package:fstapp/components/html/html_view.dart';
import 'package:fstapp/app_config.dart';
import 'package:fstapp/services/toast_helper.dart';
import 'package:fstapp/components/users/db_users.dart';

@RoutePage(name: 'UnitBankAccountsListRoute')
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
  int? _organizationId;

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  void _showError(String message) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
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
      // 1. Get Organization ID (if admin)
      // 1. Get Organization ID (if admin)
      final orgData = await DbUsers.getCurrentOrganization();
      _organizationId = orgData?.id;

      // 2. Load Unit Accounts
      _unitAccounts =
          await DbBankAccounts.getBankAccountsForUnit(widget.unitId);

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

  Future<void> _addOrEditAccount([BankAccountModel? account]) async {
    // If editing existing, we check if it is org account

    if (account == null) {
      // Creation Flow
      // Create new account logic
      // However, we need to link it to the current Unit too? Ideally yes.

      BankAccountModel? selectedAccount;
      bool createNew = true;

      final choice = await showDialog<String>(
        context: context,
        builder: (context) => SimpleDialog(
          title: Text(BankAccountStrings.addBankAccount),
          children: [
            SimpleDialogOption(
              onPressed: () => Navigator.pop(context, 'new'),
              child: Padding(
                padding: const EdgeInsets.all(8.0),
                child: Text(BankAccountStrings.createNewAccount),
              ),
            ),
            SimpleDialogOption(
              onPressed: () => Navigator.pop(context, 'link'),
              child: Padding(
                padding: const EdgeInsets.all(8.0),
                child: Text(BankAccountStrings.linkExistingAccount),
              ),
            ),
          ],
        ),
      );

      if (choice == null) return;
      createNew = choice == 'new';

      if (!createNew) {
        // Link Existing: Fetch ALL Org accounts + My Admin accounts
        setState(() => _isLoading = true);
        List<BankAccountModel> availableAccounts = [];
        try {
          if (_organizationId != null) {
            availableAccounts =
                await DbBankAccounts.getBankAccountsForOrganization(
                    _organizationId!);
          }
          // Also fetch "My Admin" just in case they are not in Org view but I am admin
          final myAccounts = await DbBankAccounts.getMyAdminBankAccounts();
          // Merge and distinct
          final existingIds = availableAccounts.map((a) => a.id).toSet();
          availableAccounts
              .addAll(myAccounts.where((a) => !existingIds.contains(a.id)));

          // Filter out already linked to THIS unit
          final linkedIds = _unitAccounts.map((a) => a.id).toSet();
          availableAccounts = availableAccounts
              .where((a) => !linkedIds.contains(a.id))
              .toList();
        } catch (e) {
          // ignore
        } finally {
          if (mounted) setState(() => _isLoading = false);
        }

        if (availableAccounts.isEmpty) {
          if (mounted)
            ToastHelper.Show(context, "No existing accounts found to link.");
          return;
        }

        if (!mounted) return;

        selectedAccount = await showDialog<BankAccountModel>(
          context: context,
          builder: (context) => SimpleDialog(
            title: Text(BankAccountStrings.selectAccount),
            children: availableAccounts
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
      _loadData();
    }
  }

  Future<void> _unlinkAccount(BankAccountModel account) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
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
      builder: (context) => AlertDialog(
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
                    Expanded(
                      child: ReorderableListView.builder(
                        buildDefaultDragHandles: false,
                        itemCount: _unitAccounts.length,
                        onReorder: _onReorder,
                        itemBuilder: (context, index) {
                          final account = _unitAccounts[index];
                          bool canEdit = account.isAdmin;
                          return ListTile(
                            key: ValueKey(account.id),
                            title: Text(
                                account.title ?? BankAccountStrings.untitled),
                            subtitle: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                if (account.accountNumber != null)
                                  Text(account.accountNumberHumanReadable ??
                                      account.accountNumber!),
                                if (account.supportedCurrencies.isNotEmpty)
                                  Padding(
                                    padding: const EdgeInsets.only(top: 4.0),
                                    child: () {
                                      return Wrap(
                                        spacing: 4,
                                        runSpacing: 4,
                                        children: account.supportedCurrencies
                                            .map((c) {
                                          // Check if any higher priority (lower index) account has this currency
                                          bool isPrimary = true;
                                          for (int i = 0; i < index; i++) {
                                            if (_unitAccounts[i]
                                                .supportedCurrencies
                                                .contains(c)) {
                                              isPrimary = false;
                                              break;
                                            }
                                          }

                                          return Tooltip(
                                            message: isPrimary
                                                ? BankAccountStrings
                                                    .primaryAccountFor(c)
                                                : BankAccountStrings
                                                    .backupAccountFor(c),
                                            child: Container(
                                              padding:
                                                  const EdgeInsets.symmetric(
                                                      horizontal: 6,
                                                      vertical: 2),
                                              decoration: BoxDecoration(
                                                color: isPrimary
                                                    ? Colors.green.shade100
                                                    : Colors.grey.shade200,
                                                borderRadius:
                                                    BorderRadius.circular(4),
                                                border: Border.all(
                                                    color: isPrimary
                                                        ? Colors.green.shade400
                                                        : Colors.grey.shade400),
                                              ),
                                              child: Row(
                                                mainAxisSize: MainAxisSize.min,
                                                children: [
                                                  Text(c,
                                                      style: TextStyle(
                                                          fontSize: 10,
                                                          fontWeight:
                                                              FontWeight.bold,
                                                          color: isPrimary
                                                              ? Colors.green
                                                                  .shade900
                                                              : Colors
                                                                  .black87)),
                                                  if (isPrimary) ...[
                                                    const SizedBox(width: 4),
                                                    Icon(Icons.star,
                                                        size: 10,
                                                        color: Colors
                                                            .green.shade800),
                                                  ]
                                                ],
                                              ),
                                            ),
                                          );
                                        }).toList(),
                                      );
                                    }(),
                                  ),
                              ],
                            ),
                            trailing: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                IconButton(
                                  icon: Icon(
                                      canEdit ? Icons.edit : Icons.visibility),
                                  onPressed: () => _addOrEditAccount(account),
                                ),
                                IconButton(
                                  icon: const Icon(Icons.link_off),
                                  onPressed: () => _unlinkAccount(account),
                                ),
                                if (canEdit)
                                  ReorderableDragStartListener(
                                    index: index,
                                    child: const DragHandleDots(),
                                  ),
                              ],
                            ),
                          );
                        },
                      ),
                    ),
                  ],
                ),
              ),
            ),
      floatingActionButton: FloatingActionButton(
        onPressed: () => _addOrEditAccount(),
        child: const Icon(Icons.add),
      ),
    );
  }
}
