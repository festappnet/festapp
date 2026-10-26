import 'package:material_ui/material_ui.dart';
import '../occasion_sale_strings.dart';

import 'package:festapp_core/eshop.dart';
import 'package:fstapp/components/bank_accounts/views/unit_bank_account_card.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:fstapp/components/bank_accounts/views/unit_bank_accounts_screen.dart';

import 'occasion_setup_details_strings.dart';

Set<String> setupPaidCurrencies(Map<String, dynamic> data) {
  final result = <String>{};
  if (data['formEnabled'] == false) return result;
  for (final field
      in ((data['formDraft'] as Map?)?['fields'] as List? ?? [])
          .whereType<Map>()) {
    if (field['is_hidden'] == true) continue;
    for (final product
        in ((field['product_type_data'] as Map?)?['products'] as List? ?? [])
            .whereType<Map>()) {
      if (product['is_hidden'] != true &&
          (num.tryParse('${product['price']}') ?? 0) > 0) {
        result.add(product['currency_code'] as String? ?? 'CZK');
      }
    }
  }
  return result;
}

class OccasionSetupBankAccount extends StatefulWidget {
  final String draftId;
  final int unitId;
  final Map<String, dynamic> data;
  final ValueChanged<Map<String, dynamic>> onChanged;
  final Future<Map<String, dynamic>> Function()? loader;
  final Future<void> Function(BuildContext)? setup;
  const OccasionSetupBankAccount({
    super.key,
    required this.draftId,
    required this.unitId,
    required this.data,
    required this.onChanged,
    this.loader,
    this.setup,
  });
  @override
  State<OccasionSetupBankAccount> createState() =>
      _OccasionSetupBankAccountState();
}

class _OccasionSetupBankAccountState extends State<OccasionSetupBankAccount> {
  List<Map<String, dynamic>> _accounts = [];
  bool _loading = true, _canManage = false;
  String? _error;
  String get _signature =>
      (setupPaidCurrencies(widget.data).toList()..sort()).join(',');
  late String _currencies;
  @override
  void initState() {
    super.initState();
    _currencies = _signature;
    _load();
  }

  @override
  void didUpdateWidget(OccasionSetupBankAccount old) {
    super.didUpdateWidget(old);
    if (_currencies != _signature) {
      _currencies = _signature;
      _load();
    }
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final result = widget.loader != null
          ? await widget.loader!()
          : Map<String, dynamic>.from(
              await Supabase.instance.client.rpc(
                'get_occasion_setup_bank_accounts',
                params: {'p_id': widget.draftId},
              ),
            );
      if (!mounted) return;
      final required = setupPaidCurrencies(widget.data);
      final accounts = (result['accounts'] as List)
          .map((v) => Map<String, dynamic>.from(v as Map))
          .where(
            (a) =>
                Set<String>.from(a['currencies'] as List? ?? [])
                    .containsAll(required),
          )
          .toList();
      final previous = widget.data['bankAccountId'];
      final selected = accounts.where((a) => a['id'] == previous).firstOrNull;
      setState(() {
        _accounts = accounts;
        _canManage = result['canManage'] == true;
        _loading = false;
      });
      if (selected == null) {
        final first = accounts.firstOrNull;
        widget.onChanged({
          'bankAccountId': first?['id'],
          'bankAccountLabel': first == null ? '' : _label(first),
          'bankAccountFingerprint': first?['fingerprint'],
        });
      } else if (widget.data['bankAccountLabel'] != _label(selected) ||
          widget.data['bankAccountFingerprint'] != selected['fingerprint']) {
        widget.onChanged({
          'bankAccountLabel': _label(selected),
          'bankAccountFingerprint': selected['fingerprint'],
        });
      }
    } catch (_) {
      if (mounted)
        setState(() {
          _loading = false;
          _error = OccasionSetupDetailsStrings.text('bankLoadFailed');
        });
    }
  }

  String _label(Map<String, dynamic> account) =>
      '${account['title'] ?? ''} · ${account['display'] ?? ''}';
  Future<void> _setup() async {
    if (widget.setup != null) {
      await widget.setup!(context);
    } else {
      await Navigator.of(context).push(
        MaterialPageRoute<void>(
          builder: (_) => UnitBankAccountsScreen(unitId: widget.unitId),
        ),
      );
    }
    if (mounted) await _load();
  }

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      if (_loading) const LinearProgressIndicator(),
      if (_error != null) ...[
        Text(
          _error!,
          style: TextStyle(color: Theme.of(context).colorScheme.error),
        ),
        TextButton(
          onPressed: _load,
          child: Text(OccasionSetupDetailsStrings.text('reloadAccounts')),
        ),
      ],
      if (!_loading && _error == null) ...[
        if (_accounts.isEmpty)
          Text(OccasionSetupDetailsStrings.text('bankMissing'))
        else ...[
          for (final account in _accounts)
            UnitBankAccountCard(
              showSyncHelp: false,
              account: BankAccountModel.fromJson({
                ...account,
                'account_number_human_readable': account['display'],
                'supported_currencies': account['currencies'],
              }),
              primaryCurrencies: const {},
              index: 0,
              selection: Semantics(
                label: _label(account),
                child: Radio<int>(
                  value: account['id'] as int,
                  groupValue: widget.data['bankAccountId'] as int?,
                  onChanged: (id) => widget.onChanged({
                    'bankAccountId': id,
                    'bankAccountLabel': _label(account),
                    'bankAccountFingerprint': account['fingerprint'],
                  }),
                ),
              ),
            ),
        ],
        const SizedBox(height: 8),
        if (_canManage)
          Center(
            child: OutlinedButton.icon(
              onPressed: _setup,
              icon: const Icon(Icons.account_balance_outlined),
              label: Text(
                OccasionSetupDetailsStrings.text(
                  _accounts.isEmpty ? 'setupBankAccount' : 'manageBankAccounts',
                ),
              ),
            ),
          )
        else
          Text(OccasionSetupDetailsStrings.text('bankManagerNeeded')),
        if (_accounts.any(
          (account) =>
              account['id'] == widget.data['bankAccountId'] &&
              (account['bank_sync'] as Map?)?['state'] != 'connected',
        ))
          Padding(
            padding: const EdgeInsets.only(top: 12),
            child: Text(OccasionSaleStrings.text('manualPaymentsHelp')),
          ),
      ],
    ],
  );
}
