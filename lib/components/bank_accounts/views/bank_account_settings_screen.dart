import 'package:collection/collection.dart';
import 'package:fstapp/components/navigation/retained_draft_guard.dart';
import 'package:fstapp/components/navigation/navigation_paths.dart';
import 'package:auto_route/auto_route.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:fstapp/app_router.gr.dart';
import 'package:fstapp/components/navigation/routed_tab_scaffold.dart';
import 'package:fstapp/components/bank_accounts/bank_account_model.dart';
import 'package:fstapp/components/bank_accounts/db_bank_accounts.dart';
import 'package:fstapp/services/toast_helper.dart';
import 'package:fstapp/components/bank_accounts/bank_account_strings.dart';
import 'package:fstapp/components/bank_accounts/logic/iban_utils.dart';
import 'package:fstapp/components/bank_accounts/data/cz_banks.dart';
import 'package:fstapp/components/bank_accounts/views/bank_account_general_tab.dart';
import 'package:fstapp/components/bank_accounts/views/bank_account_connection_tab.dart';
import 'package:fstapp/components/bank_accounts/views/bank_account_users_tab.dart';
import 'package:timeago/timeago.dart' as timeago;

class BankAccountSettingsScreen extends StatefulWidget {
  final int unitId;
  final int? organizationId;
  final BankAccountModel account;
  final bool readOnly;

  final bool isDialog;
  final bool routed;

  const BankAccountSettingsScreen({
    super.key,
    required this.unitId,
    this.organizationId,
    required this.account,
    this.readOnly = false,
    this.isDialog = false,
    this.routed = false,
  });

  @override
  State<BankAccountSettingsScreen> createState() =>
      _BankAccountSettingsScreenState();
}

class _BankAccountSettingsScreenState extends State<BankAccountSettingsScreen>
    with SingleTickerProviderStateMixin {
  bool _useIbanInput = true;

  late TextEditingController _ibanController;
  late TextEditingController _prefixController;
  late TextEditingController _accountBodyController;
  late TextEditingController _bankCodeController;

  String? _selectedBankCode;

  late TextEditingController _titleController;
  late TextEditingController _creditorNameController;
  late TextEditingController _priorityController;
  late TextEditingController _tokenController;
  TabController? _tabController;
  DateTime? _expiryDate;

  late BankAccountModel _account;

  String? _pairingCode;
  List<String> _supportedCurrencies = [];
  bool _isSaving = false;
  List<Object?> _savedGeneral = [];
  List<Object?> _savedConnection = [];
  List<Object?> get _generalValues => [
        _titleController.text,
        _creditorNameController.text,
        _ibanController.text,
        _prefixController.text,
        _accountBodyController.text,
        _selectedBankCode,
        _supportedCurrencies.join(','),
        _useIbanInput
      ];
  List<Object?> get _connectionValues => [_tokenController.text, _expiryDate];
  bool get _hasDraft =>
      !const ListEquality<Object?>().equals(_generalValues, _savedGeneral) ||
      !const ListEquality<Object?>()
          .equals(_connectionValues, _savedConnection);

  // Validation State
  String? _ibanError;

  final _formKey = GlobalKey<FormState>();

  bool get _isReadOnly => widget.readOnly || _account.type == 'CASH';
  final String _emailDomain = "bank.festapp.net";

  @override
  void initState() {
    super.initState();
    _account = widget.account;
    _titleController = TextEditingController(text: _account.title);
    _creditorNameController = TextEditingController(
      text: _account.creditorName,
    );
    _priorityController = TextEditingController(
      text: _account.priority.toString(),
    );
    _tokenController = TextEditingController();

    _ibanController = TextEditingController(text: _account.accountNumber);
    _prefixController = TextEditingController();
    _accountBodyController = TextEditingController();
    _bankCodeController = TextEditingController();

    _pairingCode = _account.pairingCode;

    _parseInitialIban();

    bool hasData = _ibanController.text.isNotEmpty;
    bool isCzParsed = _prefixController.text.isNotEmpty ||
        _accountBodyController.text.isNotEmpty ||
        (_selectedBankCode != null);

    _useIbanInput = hasData && !isCzParsed;
    _supportedCurrencies = List.from(_account.supportedCurrencies);
    _expiryDate = _account.tokenExpiryDate;

    _ibanController.addListener(_onIbanChanged);
    _prefixController.addListener(_onHumanChanged);
    _accountBodyController.addListener(_onHumanChanged);

    _initTabController();

    if (_supportedCurrencies.isEmpty) {
      _supportedCurrencies.add('CZK');
    }

    _savedGeneral = _generalValues;
    _savedConnection = _connectionValues;
    timeago.setLocaleMessages('cs', timeago.CsMessages());
  }

  bool get _isFio {
    if (_ibanController.text.isNotEmpty && isFioBank(_ibanController.text))
      return true;
    if (_selectedBankCode != null && isFioBank(_selectedBankCode)) return true;
    return false;
  }

  @override
  void dispose() {
    _ibanController.dispose();
    _prefixController.dispose();
    _accountBodyController.dispose();
    _bankCodeController.dispose();

    _titleController.dispose();
    _creditorNameController.dispose();
    _priorityController.dispose();
    _tokenController.dispose();
    _tabController?.dispose();
    super.dispose();
  }

  void _parseInitialIban() {
    final iban = _ibanController.text.trim();
    if (iban.isNotEmpty) {
      final parsed = IbanUtils.parseCzIban(iban);
      if (parsed != null) {
        _prefixController.text = parsed.prefix == '0' ? '' : parsed.prefix;
        _accountBodyController.text = parsed.number;
        if (czBanks.containsKey(parsed.bankCode)) {
          _selectedBankCode = parsed.bankCode;
        }
      }
    }
  }

  bool _isUpdating = false;

  void _onIbanChanged() {
    if (_isUpdating) return;
    final iban = _ibanController.text.trim();

    bool isValid = IbanUtils.isValidIban(iban);
    if (iban.isNotEmpty && !isValid) {
      setState(() => _ibanError = "Invalid IBAN");
      return;
    } else {
      if (mounted && _ibanError != null) setState(() => _ibanError = null);
    }

    if (isValid && iban.toUpperCase().startsWith('CZ')) {
      final parsed = IbanUtils.parseCzIban(iban);
      if (parsed != null) {
        _isUpdating = true;
        _prefixController.text = parsed.prefix == '0' ? '' : parsed.prefix;
        _accountBodyController.text = parsed.number;
        if (czBanks.containsKey(parsed.bankCode)) {
          setState(() {
            _selectedBankCode = parsed.bankCode;
          });
        }
        _isUpdating = false;
      }
    }
  }

  void _onHumanChanged() {
    if (_isUpdating) return;

    String prefix = _prefixController.text.trim();
    String body = _accountBodyController.text.trim();
    String? bank = _selectedBankCode;

    if (body.isEmpty || bank == null) {
      return;
    }

    try {
      if (prefix.isEmpty) prefix = "0";

      String generated = IbanUtils.generateCzIban(bank, prefix, body);

      _isUpdating = true;
      if (_ibanController.text != generated) {
        _ibanController.text = generated;
        setState(() => _ibanError = null);
      }
      _isUpdating = false;
    } catch (e) {
      // Don't generate IBAN on error
    }
  }

  Future<void> _saveGeneralInfo() async {
    if (!_formKey.currentState!.validate()) return;

    if (_ibanError != null) {
      _showError("Please fix validaton errors: $_ibanError");
      return;
    }
    if (!IbanUtils.isValidIban(_ibanController.text)) {
      _showError("Invalid IBAN format");
      return;
    }

    final isCreation = _account.id == 0;

    setState(() => _isSaving = true);
    try {
      final updatedAccount = BankAccountModel(
        id: _account.id,
        title: _titleController.text,
        creditorName: _creditorNameController.text.trim().isEmpty
            ? null
            : _creditorNameController.text.trim(),
        accountNumber: _ibanController.text.trim(),
        priority: int.tryParse(_priorityController.text) ?? _account.priority,
        type: _isFio ? 'FIO' : 'OTHER',
        isAdmin: _account.isAdmin,
        supportedCurrencies: _supportedCurrencies,
        accountNumberHumanReadable: _buildLegacyHumanReadable(),
        tokenMasked: _account.tokenMasked,
        lastFetchTime: _account.lastFetchTime,
        lastFioFetchTime: _account.lastFioFetchTime,
        tokenExpiryDate: _account.tokenExpiryDate,
        pairingCode: _pairingCode,
      );
      final newId = await DbBankAccounts.updateBankAccount(
        updatedAccount,
        unitId: widget.unitId,
        organizationId: widget.organizationId,
      );
      final savedAccount = updatedAccount.copyWith(id: newId);

      if (!mounted) return;

      setState(() {
        _account = savedAccount;
        _savedGeneral = _generalValues;
      });

      if (isCreation) {
        await _regenerateToken(silent: true);
        if (widget.routed) {
          context.router.navigate(BankAccountDetailRoute(
              accountId: _account.id.toString(),
              children: [
                const BankAccountTabsRoute(
                    children: [BankAccountConnectionRoute()])
              ]));
        } else {
          _tabController?.animateTo(1);
        }
        ToastHelper.Show(
          context,
          "${BankAccountStrings.save}. ${BankAccountStrings.setupConnectionNow}",
        );
      } else {
        ToastHelper.Show(context, BankAccountStrings.save);
      }

      if (widget.isDialog && _account.pairingCode == null) {
        if (!isCreation) {
          Navigator.pop(context, savedAccount);
        }
      } else if (!isCreation && widget.isDialog) {
        Navigator.pop(context, savedAccount);
      }
    } catch (e) {
      if (e.toString().contains("ACCOUNT_NUMBER_EXISTS")) {
        _showError(BankAccountStrings.accountNumberExists);
      } else {
        _showError("$e");
      }
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  String? _buildLegacyHumanReadable() {
    if (_accountBodyController.text.isEmpty || _selectedBankCode == null)
      return null;
    String prefix = _prefixController.text.trim();
    String body = _accountBodyController.text.trim();
    if (prefix.isNotEmpty && prefix != '0') {
      return "$prefix-$body/$_selectedBankCode";
    }
    return "$body/$_selectedBankCode";
  }

  void _initTabController() {
    if (!widget.routed) _tabController = TabController(length: 3, vsync: this);
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

  Future<void> _saveToken() async {
    setState(() => _isSaving = true);
    try {
      await DbBankAccounts.updateBankAccountToken(
        _account.id,
        _tokenController.text,
        _expiryDate,
      );
      if (!mounted) return;

      final newToken = _tokenController.text;
      if (newToken.isNotEmpty) {
        final mask =
            "************${newToken.length >= 4 ? newToken.substring(newToken.length - 4) : newToken}";
        setState(() {
          _account = _account.copyWith(tokenMasked: mask);
        });
      }

      ToastHelper.Show(context, BankAccountStrings.tokenUpdated);
      _tokenController.clear();
      _savedConnection = _connectionValues;
    } catch (e) {
      if (mounted) _showError("${BankAccountStrings.errorSavingToken}: $e");
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  Future<void> _regenerateToken({bool silent = false}) async {
    if (!silent) {
      bool? confirm = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: Text(BankAccountStrings.regenerateToken),
          content: Text(BankAccountStrings.regenerateTokenConfirmation),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: Text(BankAccountStrings.cancel),
            ),
            TextButton(
              style: TextButton.styleFrom(
                foregroundColor: Theme.of(context).colorScheme.error,
              ),
              onPressed: () => Navigator.pop(context, true),
              child: Text(BankAccountStrings.regenerateToken),
            ),
          ],
        ),
      );
      if (confirm != true) return;
    }

    setState(() => _isSaving = true);
    try {
      final newToken = await DbBankAccounts.regenerateBankAccountPairingCode(
        _account.id,
      );
      setState(() {
        _pairingCode = newToken;
        _account = _account.copyWith(pairingCode: newToken);
      });
      if (!silent) {
        if (!mounted) return;
        ToastHelper.Show(context, BankAccountStrings.tokenUpdated);
      }
    } catch (e) {
      _showError("${BankAccountStrings.errorSavingToken}: $e");
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  Future<void> _showAddCurrencyDialog() async {
    final controller = TextEditingController();
    await showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(BankAccountStrings.addCurrency),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Wrap(
              spacing: 8,
              children: ['CZK', 'EUR']
                  .where((c) => !_supportedCurrencies.contains(c))
                  .map(
                    (c) => ActionChip(
                      label: Text(c),
                      onPressed: () => Navigator.pop(context, c),
                    ),
                  )
                  .toList(),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: controller,
              decoration: InputDecoration(
                labelText: BankAccountStrings.currencyCodeLabel,
                hintText: BankAccountStrings.currencyHint,
              ),
              textCapitalization: TextCapitalization.characters,
              maxLength: 3,
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text(BankAccountStrings.cancel),
          ),
          ElevatedButton(
            onPressed: () {
              final val = controller.text.toUpperCase();
              if (val.length == 3) {
                Navigator.pop(context, val);
              } else {
                ToastHelper.Show(
                  context,
                  BankAccountStrings.invalidCurrencyCode,
                );
              }
            },
            child: Text(BankAccountStrings.addCurrency),
          ),
        ],
      ),
    ).then((val) {
      if (val != null && val is String && val.length == 3) {
        if (!_supportedCurrencies.contains(val)) {
          setState(() => _supportedCurrencies.add(val));
        }
      }
    });
  }

  Widget _general(BuildContext context) => BankAccountGeneralTab(
        isReadOnly: _isReadOnly,
        isSaving: _isSaving,
        formKey: _formKey,
        titleController: _titleController,
        creditorNameController: _creditorNameController,
        ibanController: _ibanController,
        prefixController: _prefixController,
        accountBodyController: _accountBodyController,
        useIbanInput: _useIbanInput,
        onUseIbanInputChanged: (v) => setState(() => _useIbanInput = v),
        selectedBankCode: _selectedBankCode,
        onSelectedBankCodeChanged: (v) => setState(() => _selectedBankCode = v),
        ibanError: _ibanError,
        supportedCurrencies: _supportedCurrencies,
        onAddCurrency: _showAddCurrencyDialog,
        onRemoveCurrency: (c) => setState(() => _supportedCurrencies.remove(c)),
        buildLegacyHumanReadable: _buildLegacyHumanReadable,
        onSave: _saveGeneralInfo,
        onIbanChanged: _onIbanChanged,
        onHumanChanged: _onHumanChanged,
      );
  Widget _connection(BuildContext context) => BankAccountConnectionTab(
        account: _account,
        isReadOnly: _isReadOnly,
        isFio: _isFio,
        isSaving: _isSaving,
        pairingCode: _pairingCode,
        emailDomain: _emailDomain,
        onRegenerateToken: _regenerateToken,
        tokenController: _tokenController,
        expiryDate: _expiryDate,
        onExpiryDateChanged: (d) => setState(() => _expiryDate = d),
        onSaveToken: _saveToken,
      );
  Widget _users(BuildContext context) => BankAccountUsersTab(
        accountId: _account.id,
        unitId: widget.unitId,
        isReadOnly: _isReadOnly,
      );
  @override
  Widget build(BuildContext context) {
    if (widget.routed) {
      return NavigationDraftBoundary(
          isDirty: () => _hasDraft,
          child: BankAccountEditorScope(
              general: _general,
              connection: _connection,
              users: _users,
              child: RoutedBankAccountDialog(
                  title: _account.title ??
                      BankAccountStrings.bankAccountSettingsTitle,
                  onClose: () => RetainedDraftGuard.instance.leaveOwner(
                      context,
                      () => context.router
                          .replaceAll([UnitBankAccountsListRoute()])),
                  child: const AutoRouter())));
    }
    final content = Column(
      children: [
        if (widget.isDialog)
          Padding(
            padding: const EdgeInsets.all(16.0),
            child: Text(
              _account.title ?? BankAccountStrings.bankAccountSettingsTitle,
              style: Theme.of(context).textTheme.titleLarge,
            ),
          ),
        TabBar(
          controller: _tabController,
          labelColor: Theme.of(context).primaryColor,
          tabs: [
            Tab(text: BankAccountStrings.generalTab),
            Tab(text: BankAccountStrings.bankConnectionTab),
            Tab(text: BankAccountStrings.usersTab),
          ],
        ),
        Expanded(
          child: TabBarView(
            controller: _tabController,
            children: [
              _general(context),
              _connection(context),
              _users(context),
            ],
          ),
        ),
        if (widget.isDialog)
          Padding(
            padding: const EdgeInsets.all(8.0),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: Text(BankAccountStrings.cancel),
                ),
              ],
            ),
          ),
      ],
    );

    if (widget.isDialog) {
      return Dialog(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 600, maxHeight: 800),
          child: content,
        ),
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: Text(
          _account.title ?? BankAccountStrings.bankAccountSettingsTitle,
        ),
      ),
      body: content,
    );
  }
}

/// URL-backed editor with the same compact presentation as the creation dialog.
class RoutedBankAccountDialog extends StatefulWidget {
  final String title;
  final Widget child;
  final VoidCallback onClose;
  const RoutedBankAccountDialog(
      {super.key,
      required this.title,
      required this.child,
      required this.onClose});
  @override
  State<RoutedBankAccountDialog> createState() =>
      _RoutedBankAccountDialogState();
}

class _RoutedBankAccountDialogState extends State<RoutedBankAccountDialog> {
  final _overlay = OverlayPortalController();
  bool _visible = false;
  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // Retained inactive tabs and denied administration scopes must hide the modal.
    final visible =
        TickerMode.of(context) && (ModalRoute.of(context)?.isCurrent ?? true);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      if (_visible != visible) setState(() => _visible = visible);
      // Keep the native child router mounted while a retained section is hidden.
      if (!_overlay.isShowing) _overlay.show();
    });
  }

  @override
  Widget build(BuildContext context) => OverlayPortal.targetsRootOverlay(
      controller: _overlay,
      overlayChildBuilder: _buildDialog,
      child: const SizedBox.shrink());
  Widget _buildDialog(BuildContext context) => Offstage(
      offstage: !_visible,
      child: BlockSemantics(
        child: FocusScope(
            autofocus: true,
            canRequestFocus: _visible,
            child: CallbackShortcuts(
              bindings: {
                const SingleActivator(LogicalKeyboardKey.escape): widget.onClose
              },
              child: Stack(fit: StackFit.expand, children: [
                ModalBarrier(
                    color: Colors.black54,
                    onDismiss: widget.onClose,
                    semanticsLabel: MaterialLocalizations.of(context)
                        .modalBarrierDismissLabel),
                Dialog(
                    child: ConstrainedBox(
                  constraints:
                      const BoxConstraints(maxWidth: 600, maxHeight: 800),
                  child: Column(children: [
                    Padding(
                        padding: const EdgeInsets.all(16),
                        child: Text(widget.title,
                            style: Theme.of(context).textTheme.titleLarge)),
                    Expanded(child: widget.child),
                    Padding(
                        padding: const EdgeInsets.all(8),
                        child: Row(
                            mainAxisAlignment: MainAxisAlignment.end,
                            children: [
                              TextButton(
                                  onPressed: widget.onClose,
                                  child: Text(BankAccountStrings.cancel)),
                            ])),
                  ]),
                )),
              ]),
            )),
      ));
}

class BankAccountEditorScope extends InheritedWidget {
  final WidgetBuilder general;
  final WidgetBuilder connection;
  final WidgetBuilder users;
  const BankAccountEditorScope(
      {super.key,
      required this.general,
      required this.connection,
      required this.users,
      required super.child});
  static BankAccountEditorScope of(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<BankAccountEditorScope>()!;
  @override
  bool updateShouldNotify(BankAccountEditorScope oldWidget) => true;
}

@RoutePage()
class BankAccountGeneralPage extends StatelessWidget {
  const BankAccountGeneralPage({super.key});
  @override
  Widget build(BuildContext context) =>
      BankAccountEditorScope.of(context).general(context);
}

@RoutePage()
class BankAccountConnectionPage extends StatelessWidget {
  const BankAccountConnectionPage({super.key});
  @override
  Widget build(BuildContext context) =>
      BankAccountEditorScope.of(context).connection(context);
}

@RoutePage()
class BankAccountUsersPage extends StatelessWidget {
  const BankAccountUsersPage({super.key});
  @override
  Widget build(BuildContext context) =>
      BankAccountEditorScope.of(context).users(context);
}

@RoutePage()
class BankAccountTabsPage extends StatelessWidget {
  const BankAccountTabsPage({super.key});
  @override
  Widget build(BuildContext context) {
    Localizations.localeOf(context);
    return RoutedTabScaffold(tabs: [
      RoutedTabDefinition(
          slug: NavigationPaths.general,
          route: const BankAccountGeneralRoute(),
          label: BankAccountStrings.generalTab,
          icon: Icons.account_balance),
      RoutedTabDefinition(
          slug: NavigationPaths.connection,
          route: const BankAccountConnectionRoute(),
          label: BankAccountStrings.bankConnectionTab,
          icon: Icons.link),
      RoutedTabDefinition(
          slug: NavigationPaths.users,
          route: const BankAccountUsersRoute(),
          label: BankAccountStrings.usersTab,
          icon: Icons.people),
    ]);
  }
}
