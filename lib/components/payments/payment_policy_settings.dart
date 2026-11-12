import 'package:material_ui/material_ui.dart';
import 'package:fstapp/widgets/app_dialog.dart';
import 'package:fstapp/components/_shared/common_strings.dart';
import 'package:fstapp/data_services/rights_service.dart';

import '../forms/payment_method_strings.dart';
import 'payment_policy.dart';
import 'db_payment_policy.dart';

/// One installed-method list for both tenant and organizer policy.
class PaymentPolicySettings extends StatefulWidget {
  const PaymentPolicySettings({
    super.key,
    required this.organizationId,
    this.unitId,
    this.onChanged,
    this.onConfigure,
    this.configureMethods = const {},
  });
  final int organizationId;
  final int? unitId;
  final ValueChanged<String>? onConfigure;
  final Set<String> configureMethods;
  final ValueChanged<PaymentPolicy>? onChanged;
  @override
  State<PaymentPolicySettings> createState() => _PaymentPolicySettingsState();
}

class _PaymentPolicySettingsState extends State<PaymentPolicySettings> {
  PaymentPolicy? _policy;
  bool _busy = false, _failed = false;
  int _generation = 0;
  final _policies = DbPaymentPolicy();
  String t(String key) => PaymentMethodStrings.text(key);
  @override
  void initState() {
    super.initState();
    RightsService.occasionLinkModelNotifier.addListener(_rightsChanged);
    _load();
  }

  @override
  void didUpdateWidget(covariant PaymentPolicySettings old) {
    super.didUpdateWidget(old);
    if (old.organizationId != widget.organizationId ||
        old.unitId != widget.unitId) {
      _load();
    }
  }

  @override
  void dispose() {
    _generation++;
    RightsService.occasionLinkModelNotifier.removeListener(_rightsChanged);
    super.dispose();
  }

  void _rightsChanged() => _load();
  Future<void> _load() async {
    final generation = ++_generation;
    setState(() {
      _policy = null;
      _failed = false;
    });
    try {
      final policy = await _policies.load(widget.organizationId, widget.unitId);
      if (!mounted || generation != _generation) return;
      setState(() => _policy = policy);
      widget.onChanged?.call(policy);
    } catch (_) {
      if (mounted && generation == _generation) setState(() => _failed = true);
    }
  }

  Future<void> _change(
    String method,
    PaymentPolicyMode mode, {
    bool preferred = false,
  }) async {
    if (_busy) return;
    final generation = _generation;
    final change = PaymentPolicyChange(
      organizationId: widget.organizationId,
      unitId: widget.unitId,
      method: method,
      mode: mode,
      preferred: preferred,
    );
    setState(() => _busy = true);
    try {
      final preview = await _policies.preview(change);
      if (!mounted || generation != _generation) return;
      final impact = preview.impact;
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (context) => AppAlertDialog(
          title: Text(t('policyConfirm')),
          content: Text(
            '${t('policyImpact')}\n${t('policyOpen')}: ${impact.openCollections}\n${t('policyPending')}: ${impact.pendingRequests}\n${t('policyIssued')}: ${impact.issuedReferences}\n${t('policyBankInstructions')}: ${impact.pendingBankInstructions}\n${t('policyProviderIntents')}: ${impact.undispatchedIntents} / ${impact.dispatchedIntents} / ${impact.unknownIntents}\n${t('policyObligations')}: ${impact.obligations}',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: Text(CommonStrings.cancel),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: Text(CommonStrings.save),
            ),
          ],
        ),
      );
      if (confirmed != true || !mounted || generation != _generation) return;
      await _policies.command(preview);
      await RightsService.refreshAfterAuthorizationChange();
      await _load();
    } catch (_) {
      if (mounted && generation == _generation) setState(() => _failed = true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_policy == null) {
      return ListTile(
        title: Text(t('policyTitle')),
        subtitle: Text(t(_failed ? 'policyLoadFailed' : 'policyLoading')),
        trailing: _failed
            ? IconButton(
                tooltip: t('policyRetry'),
                onPressed: _load,
                icon: const Icon(Icons.refresh),
              )
            : const SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(),
              ),
      );
    }
    final methods = _policy!.methods;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(t('policyTitle'), style: Theme.of(context).textTheme.titleLarge),
        Text(t(widget.unitId == null ? 'policyTenantHint' : 'policyUnitHint')),
        if (_failed)
          Text(
            t('policySaveFailed'),
            style: TextStyle(color: Theme.of(context).colorScheme.error),
          ),
        for (final entry in methods.entries)
          ListTile(
            title: Text(t(entry.key)),
            subtitle: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '${t(entry.value.enabled ? 'policyEnabled' : 'policyDisabled')} - ${t(entry.value.origin == PaymentPolicyOrigin.unit ? 'policyUnit' : 'policyTenant')}',
                ),
                if (widget.unitId != null)
                  Text(
                    t(
                      entry.value.configured
                          ? 'policyConfigured'
                          : 'policyNotConfigured',
                    ),
                  ),
                if (widget.onConfigure != null &&
                    widget.configureMethods.contains(entry.key) &&
                    entry.value.canConfigure)
                  TextButton(
                    onPressed: _busy
                        ? null
                        : () => widget.onConfigure!(entry.key),
                    child: Text(t('policyConfigure')),
                  ),
              ],
            ),
            trailing: DropdownButton<PaymentPolicyMode>(
              value: widget.unitId == null
                  ? (entry.value.organizationEnabled
                        ? PaymentPolicyMode.enabled
                        : PaymentPolicyMode.disabled)
                  : entry.value.mode,
              onChanged: _busy
                  ? null
                  : (mode) {
                      if (mode != null) _change(entry.key, mode);
                    },
              items: [
                if (widget.unitId != null)
                  DropdownMenuItem(
                    value: PaymentPolicyMode.inherit,
                    child: Text(t('policyInherit')),
                  ),
                DropdownMenuItem(
                  value: PaymentPolicyMode.enabled,
                  child: Text(t('policyEnabled')),
                ),
                DropdownMenuItem(
                  value: PaymentPolicyMode.disabled,
                  child: Text(t('policyDisabled')),
                ),
              ],
            ),
            leading: IconButton(
              tooltip: t('policyPreferred'),
              icon: Icon(
                _policy!.preferredMethod == entry.key
                    ? Icons.star
                    : Icons.star_border,
              ),
              onPressed: _busy || !entry.value.enabled
                  ? null
                  : () => _change(
                      entry.key,
                      widget.unitId == null
                          ? PaymentPolicyMode.enabled
                          : entry.value.mode,
                      preferred: true,
                    ),
            ),
          ),
      ],
    );
  }
}
