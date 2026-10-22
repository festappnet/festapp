import 'package:flutter/material.dart';
import 'package:fstapp/components/_shared/common_strings.dart';
import 'package:url_launcher/url_launcher.dart';
import 'card_refund_decision_api.dart';
import 'card_refund_decision_dialog.dart';
import 'card_refund_decision_strings.dart';

/// Reads the order-editor DTO; never infers Stripe identity from public data.
class CardRefundDecisionPanel extends StatefulWidget {
  const CardRefundDecisionPanel(
      {super.key,
      required this.orderId,
      required this.onChanged,
      this.allowEdit = true,
      this.api});
  final int orderId;
  final Future<void> Function() onChanged;
  final bool allowEdit;
  final CardRefundDecisionApi? api;
  @override
  State<CardRefundDecisionPanel> createState() =>
      _CardRefundDecisionPanelState();
}

class _CardRefundDecisionPanelState extends State<CardRefundDecisionPanel> {
  late final CardRefundDecisionApi _api =
      widget.api ?? SupabaseCardRefundDecisionApi();
  CardRefundDetail? _detail;
  bool _loading = true, _failed = false;
  int _generation = 0;
  String t(String key) => CardRefundDecisionStrings.text(key);
  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void didUpdateWidget(CardRefundDecisionPanel oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.orderId != widget.orderId) _load();
  }

  Future<void> _load() async {
    final generation = ++_generation;
    setState(() {
      _loading = true;
      _failed = false;
      _detail = null;
    });
    try {
      final detail = await _api.read(widget.orderId);
      if (mounted && generation == _generation) {
        setState(() => _detail = detail);
      }
    } catch (_) {
      if (mounted && generation == _generation) setState(() => _failed = true);
    } finally {
      if (mounted && generation == _generation) {
        setState(() => _loading = false);
      }
    }
  }

  Future<void> _decide() async {
    final saved = await showDialog<bool>(
        context: context,
        barrierDismissible: false,
        builder: (_) => CardRefundDecisionDialog(detail: _detail!, api: _api));
    if (saved == true && mounted) {
      await widget.onChanged();
      if (mounted) await _load();
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) return const LinearProgressIndicator();
    if (_failed) {
      return Row(children: [
        Expanded(child: Text(t('loadFailed'))),
        TextButton(onPressed: _load, child: Text(CommonStrings.retry)),
      ]);
    }
    final detail = _detail;
    if (detail == null) return const SizedBox.shrink();
    final decision = detail.decision;
    return Card(
      elevation: 0,
      margin: const EdgeInsets.symmetric(vertical: 12),
      shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(8),
          side:
              BorderSide(color: Theme.of(context).colorScheme.outlineVariant)),
      child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(t('title'), style: Theme.of(context).textTheme.titleMedium),
              const SizedBox(height: 8),
              Text(
                  '${t('refunded')}: ${CardRefundDecisionStrings.amount(detail.refundedMinor, detail.currency, locale: Localizations.localeOf(context).toLanguageTag())}'),
              const SizedBox(height: 8),
              Text(t('explanation')),
              if (detail.reconciliationPending) ...[
                const SizedBox(height: 8),
                Text(t('pending')),
              ],
              if (decision != null) ...[
                const SizedBox(height: 12),
                Text(
                    t(decision['isCurrent'] == true
                        ? 'currentDecision'
                        : 'previousDecision'),
                    style: Theme.of(context).textTheme.titleSmall),
                Text(t(
                    decision['action'] == 'keep' ? 'keep' : 'cancelSelected')),
                if (decision['action'] == 'cancel_selected')
                  for (final ticket in detail.tickets.where((ticket) =>
                      (decision['ticketIds'] as List? ?? const [])
                          .contains(ticket.id)))
                    Text(ticket.label),
                if (decision['note'] is String) Text(decision['note']),
              ] else if (detail.refundedMinor > 0) ...[
                const SizedBox(height: 8),
                Text(t('noDecision')),
              ],
              const SizedBox(height: 12),
              Wrap(spacing: 8, runSpacing: 8, children: [
                if (detail.canDecide)
                  OutlinedButton.icon(
                      onPressed: widget.allowEdit ? _decide : null,
                      icon: const Icon(Icons.fact_check_outlined),
                      label: Text(t('decide'))),
                if (detail.dashboardUri != null)
                  TextButton.icon(
                      onPressed: () => launchUrl(detail.dashboardUri!,
                          mode: LaunchMode.externalApplication),
                      icon: const Icon(Icons.open_in_new),
                      label: Text(t('dashboard'))),
                TextButton(onPressed: _load, child: Text(t('refresh'))),
              ]),
            ],
          )),
    );
  }
}
