import 'package:flutter/material.dart';
import 'package:fstapp/app_config.dart';
import 'package:fstapp/components/bank_accounts/bank_account_model.dart';
import 'package:fstapp/components/bank_accounts/bank_account_strings.dart';
import 'package:fstapp/components/bank_accounts/db_bank_accounts.dart';
import 'package:fstapp/components/users/db_users.dart';
import 'package:fstapp/services/dialog_helper.dart';
import 'package:fstapp/services/app_logger.dart';
import 'package:fstapp/services/toast_helper.dart';

class BankAccountUsersTab extends StatefulWidget {
  final int accountId;
  final int unitId;
  final bool isReadOnly;

  const BankAccountUsersTab({
    super.key,
    required this.accountId,
    required this.unitId,
    required this.isReadOnly,
  });

  @override
  State<BankAccountUsersTab> createState() => _BankAccountUsersTabState();
}

class _BankAccountUsersTabState extends State<BankAccountUsersTab> {
  List<BankAccountUser> _users = [];
  bool _isLoadingUsers = false;

  @override
  void initState() {
    super.initState();
    _loadUsers();
  }

  Future<void> _loadUsers() async {
    setState(() => _isLoadingUsers = true);
    try {
      final users = await DbBankAccounts.getBankAccountUsers(widget.accountId,
          unitId: widget.unitId);
      if (mounted) {
        setState(() {
          _users = users;
          _isLoadingUsers = false;
        });
      }
    } catch (e) {
      if (mounted) setState(() => _isLoadingUsers = false);
      AppLogger.error("Error loading users: $e");
    }
  }

  void _showError(String message) {
    if (!mounted) return;
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

  Future<void> _addUser() async {
    setState(() => _isLoadingUsers = true);
    try {
      final allUnitUsers =
          await DbUsers.getAllUsersBasicsForUnit(widget.unitId);

      final currentIds = _users.map((u) => u.userId).toSet();
      final availableUsers =
          allUnitUsers.where((u) => !currentIds.contains(u.id)).toList();

      if (mounted) setState(() => _isLoadingUsers = false);

      if (availableUsers.isEmpty) {
        if (mounted) {
          ToastHelper.Show(context, BankAccountStrings.noMoreUsersToAdd);
        }
        return;
      }

      if (!mounted) return;
      DialogHelper.chooseUser(context, (chosenUser) async {
        if (chosenUser.id == null || chosenUser.email == null) {
          _showError(BankAccountStrings.errorUpdatingUser);
          return;
        }

        bool isAdmin = true;
        bool isSupport = false;

        await showDialog(
          context: context,
          builder: (context) => StatefulBuilder(
            builder: (context, setState) => AlertDialog(
              title: Text(
                  '${BankAccountStrings.addUser}: ${chosenUser.name ?? chosenUser.email}'),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 8.0),
                    child: Text(
                      BankAccountStrings.addUserExplanation,
                      style:
                          const TextStyle(fontSize: 14, color: Colors.grey),
                    ),
                  ),
                  CheckboxListTile(
                    title: Text(BankAccountStrings.isAdminLabel),
                    value: isAdmin,
                    onChanged: (v) => setState(() => isAdmin = v!),
                  ),
                  if (AppConfig.showBankSupportRole)
                    CheckboxListTile(
                      title: Text(BankAccountStrings.isSupportLabel),
                      value: isSupport,
                      onChanged: (v) => setState(() => isSupport = v!),
                    ),
                  if (isAdmin)
                    Padding(
                      padding: const EdgeInsets.all(8.0),
                      child: Text(
                        BankAccountStrings.adminInfoText,
                        style: const TextStyle(
                            fontSize: 14, color: Colors.grey),
                      ),
                    ),
                ],
              ),
              actions: [
                TextButton(
                    onPressed: () => Navigator.pop(context),
                    child: Text(BankAccountStrings.cancel)),
                ElevatedButton(
                  onPressed: () async {
                    Navigator.pop(context);
                    await _performUpdateUser(
                        chosenUser.email!, isAdmin, isSupport);
                  },
                  child: Text(BankAccountStrings.add),
                ),
              ],
            ),
          ),
        );
      }, availableUsers, BankAccountStrings.add);
    } catch (e) {
      if (mounted) setState(() => _isLoadingUsers = false);
      _showError("Error loading users: $e");
    }
  }

  Future<void> _editUser(BankAccountUser user) async {
    bool isAdmin = user.isAdmin;
    bool isSupport = user.isSupport;

    await showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setState) => AlertDialog(
          title: Text(
              '${BankAccountStrings.editRole}: ${user.name ?? user.email}'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              CheckboxListTile(
                title: Text(BankAccountStrings.isAdminLabel),
                value: isAdmin,
                onChanged: (v) => setState(() => isAdmin = v!),
              ),
              if (isAdmin)
                Padding(
                  padding: const EdgeInsets.all(8.0),
                  child: Text(
                    BankAccountStrings.checkAdminInfo,
                    style:
                        const TextStyle(fontSize: 14, color: Colors.grey),
                  ),
                ),
            ],
          ),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(context),
                child: Text(BankAccountStrings.cancel)),
            ElevatedButton(
              onPressed: () async {
                Navigator.pop(context);
                if (user.email != null) {
                  _performUpdateUser(user.email!, isAdmin, isSupport);
                }
              },
              child: Text(BankAccountStrings.save),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _performUpdateUser(
      String email, bool isAdmin, bool isSupport) async {
    setState(() => _isLoadingUsers = true);
    try {
      await DbBankAccounts.updateBankAccountUser(
          widget.accountId, email, isAdmin, isSupport);
      await _loadUsers();
    } catch (e) {
      _showError("${BankAccountStrings.errorUpdatingUser}: $e");
      if (mounted) setState(() => _isLoadingUsers = false);
    }
  }

  Future<void> _removeUser(BankAccountUser user) async {
    setState(() => _isLoadingUsers = true);
    try {
      if (user.email == null) {
        _showError("${BankAccountStrings.errorRemovingUser}: Email missing");
        setState(() => _isLoadingUsers = false);
        return;
      }
      await DbBankAccounts.removeBankAccountUser(
          widget.accountId, user.email!);
      await _loadUsers();
    } catch (e) {
      _showError("${BankAccountStrings.errorRemovingUser}: $e");
      if (mounted) setState(() => _isLoadingUsers = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoadingUsers) {
      return const Center(child: CircularProgressIndicator());
    }

    return Column(
      children: [
        if (!widget.isReadOnly)
          Padding(
            padding: const EdgeInsets.all(8.0),
            child: ElevatedButton.icon(
              icon: const Icon(Icons.add),
              label: Text(BankAccountStrings.addUser),
              onPressed: _addUser,
            ),
          ),
        Expanded(
          child: ListView.builder(
            itemCount: _users.length,
            itemBuilder: (context, index) {
              final user = _users[index];
              final fullName = [user.name, user.surname]
                  .where((s) => s != null && s.isNotEmpty)
                  .join(' ');
              final displayName = fullName.isNotEmpty
                  ? "$fullName (${user.email ?? ''})"
                  : (user.email ?? 'Unknown');

              return ListTile(
                title: Text(displayName),
                subtitle: Wrap(
                  spacing: 8,
                  children: [
                    if (user.isAdmin)
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 8, vertical: 2),
                        decoration: BoxDecoration(
                          color: Colors.orange.shade100,
                          borderRadius: BorderRadius.circular(12),
                          border:
                              Border.all(color: Colors.orange.shade300),
                        ),
                        child: Text(BankAccountStrings.isAdminLabel,
                            style: TextStyle(
                                fontSize: 12,
                                color: Colors.orange.shade900)),
                      ),
                    if (AppConfig.showBankSupportRole && user.isSupport)
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 8, vertical: 2),
                        decoration: BoxDecoration(
                          color: Colors.blue.shade100,
                          borderRadius: BorderRadius.circular(12),
                          border:
                              Border.all(color: Colors.blue.shade300),
                        ),
                        child: Text(BankAccountStrings.isSupportLabel,
                            style: TextStyle(
                                fontSize: 12,
                                color: Colors.blue.shade900)),
                      ),
                  ],
                ),
                trailing: widget.isReadOnly
                    ? null
                    : Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          IconButton(
                              icon: const Icon(Icons.edit),
                              onPressed: () => _editUser(user)),
                          IconButton(
                              icon: const Icon(Icons.delete),
                              onPressed: () => _removeUser(user)),
                        ],
                      ),
              );
            },
          ),
        ),
      ],
    );
  }
}
