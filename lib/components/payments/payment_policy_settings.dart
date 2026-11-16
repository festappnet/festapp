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
    this.showHeading = true,
    this.onConfigure,
    this.configureMethods = const {},
  });
  final bool showHeading;
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
    final methodPolicy = _policy?.methods[method];
    if (_busy || methodPolicy == null) return;
    if (widget.unitId != null &&
        (!methodPolicy.organizationEnabled ||
            (method == 'cash' && mode != methodPolicy.mode))) {
      return;
    }
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
    final methods = _policy!.methods.entries
        .where(
          (entry) => widget.unitId == null || entry.value.organizationEnabled,
        )
        .toList();
    final canChoosePreferred =
        methods.where((entry) => entry.value.enabled).length > 1;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (widget.showHeading) ...[
          Text(t('policyTitle'), style: Theme.of(context).textTheme.titleLarge),
          Text(
            t(widget.unitId == null ? 'policyTenantHint' : 'policyUnitHint'),
          ),
        ],
        if (_failed)
          Text(
            t('policySaveFailed'),
            style: TextStyle(color: Theme.of(context).colorScheme.error),
          ),
        if (methods.isEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 16),
            child: Text(t('policyNoMethods')),
          ),
        for (final entry in methods)
          _methodTile(entry.key, entry.value, canChoosePreferred),
      ],
    );
  }

  Widget _methodTile(
    String method,
    PaymentMethodPolicy policy,
    bool canChoosePreferred,
  ) {
    final cashIsManaged = widget.unitId != null && method == 'cash';
    final enabled = widget.unitId == null
        ? policy.organizationEnabled
        : policy.enabled;
    final canConfigure =
        widget.onConfigure != null &&
        widget.configureMethods.contains(method) &&
        policy.canConfigure;
    return ListTile(
      contentPadding: EdgeInsets.zero,
      title: Text(t(method)),
      subtitle: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(t(enabled ? 'policyEnabled' : 'policyDisabled')),
          if (cashIsManaged) Text(t('policyCashManaged')),
          if (widget.unitId != null && method != 'cash' && enabled)
            Text(
              t(policy.configured ? 'policyConfigured' : 'policyNotConfigured'),
            ),
          if (canConfigure)
            TextButton(
              onPressed: _busy ? null : () => widget.onConfigure!(method),
              child: Text(t('policyConfigure')),
            ),
        ],
      ),
      trailing: Semantics(
        label: t(method),
        child: Switch(
          key: ValueKey('payment-policy-$method'),
          value: enabled,
          onChanged: _busy || cashIsManaged
              ? null
              : (value) => _change(
                  method,
                  value
                      ? (widget.unitId == null
                            ? PaymentPolicyMode.enabled
                            : PaymentPolicyMode.inherit)
                      : PaymentPolicyMode.disabled,
                ),
        ),
      ),
      leading: canChoosePreferred
          ? IconButton(
              tooltip: t('policyPreferred'),
              isSelected: _policy!.preferredMethod == method,
              icon: const Icon(Icons.star_border),
              selectedIcon: const Icon(Icons.star),
              onPressed: _busy || !policy.enabled
                  ? null
                  : () => _change(
                      method,
                      widget.unitId == null
                          ? PaymentPolicyMode.enabled
                          : policy.mode,
                      preferred: true,
                    ),
            )
          : null,
    );
  }
}
