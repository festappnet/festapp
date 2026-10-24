import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import '../card_payment_strings.dart';

/// Safe payment projection. Write actions are supplied by the owner of a
/// separate payment capability, never obtained from the read projection.
class CardPaymentStatus extends StatefulWidget {
  const CardPaymentStatus(
      {super.key, required this.payment, this.onPay, this.onRefresh});
  final Map<String, dynamic> payment;
  final Future<void> Function()? onPay;
  final VoidCallback? onRefresh;
  static const states = {
    'preparing',
    'open',
    'pending',
    'declined',
    'paid',
    'expired',
    'action_required',
    'refund_pending',
    'partially_refunded',
    'refunded',
    'disputed'
  };
  static String stateOf(Map payment) => states.contains(payment['status'])
      ? payment['status'] as String
      : 'unknown';
  static bool canContinue(Map payment) =>
      payment['method'] == 'stripe' &&
      {'open', 'declined', 'preparing'}.contains(stateOf(payment)) &&
      !{'hold', 'revoked'}.contains(payment['admissionState']) &&
      payment['allowedActions'] is List &&
      (payment['allowedActions'] as List).contains('pay');
  static String? formatMoney(dynamic value, dynamic currency, String locale) {
    if (value == null ||
        currency is! String ||
        !RegExp(r'^[A-Z]{3}$').hasMatch(currency) ||
        !RegExp(r'^(0|[1-9][0-9]*)(\.[0-9]{1,2})?$').hasMatch(value.toString()))
      return null;
    return NumberFormat.currency(locale: locale, name: currency)
        .format(num.parse(value.toString()));
  }

  @override
  State<CardPaymentStatus> createState() => _CardPaymentStatusState();
}

class _CardPaymentStatusState extends State<CardPaymentStatus> {
  bool _busy = false;
  bool _uncertain = false;
  @override
  void didUpdateWidget(CardPaymentStatus oldWidget) {
    super.didUpdateWidget(oldWidget);
    final oldRevision = oldWidget.payment['revision'];
    final revision = widget.payment['revision'];
    if (widget.payment['status'] != oldWidget.payment['status'] ||
        (oldRevision is num && revision is num && revision > oldRevision))
      _uncertain = false;
  }

  Future<void> _pay() async {
    if (_busy || _uncertain || widget.onPay == null) return;
    setState(() => _busy = true);
    try {
      await widget.onPay!();
    } catch (_) {
      if (mounted) setState(() => _uncertain = true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final payment = widget.payment;
    final onPay = widget.onPay;
    final onRefresh = widget.onRefresh;
    final state = _uncertain ? 'unknown' : CardPaymentStatus.stateOf(payment);
    final locale = context.locale.toLanguageTag();
    String? money(dynamic value) =>
        CardPaymentStatus.formatMoney(value, payment['currency'], locale);

    Widget paragraph(String text) => Padding(
        padding: const EdgeInsets.only(bottom: 16),
        child: Text(text, style: Theme.of(context).textTheme.bodyLarge));
    final delivery = payment['deliveryState'];
    return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(CardPaymentStrings.text('title'),
              style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 16),
          Semantics(
              liveRegion: true,
              child: paragraph(CardPaymentStrings.text(state))),
          for (final key in ['amount', 'received', 'returned'])
            if (money(payment[key]) != null)
              paragraph(
                  '${CardPaymentStrings.text(key)}: ${money(payment[key])}'),
          if (payment['reservationExpiresAt'] is String &&
              {'open', 'declined'}.contains(state))
            if (DateTime.tryParse(payment['reservationExpiresAt'])
                case final DateTime date)
              paragraph(
                  '${CardPaymentStrings.text('reservation')}: ${DateFormat.yMd(locale).add_jm().format(date.toLocal())}'),
          if (payment['admissionState'] == 'hold' && state != 'disputed')
            paragraph(CardPaymentStrings.text('admissionHold')),
          if (state == 'paid')
            paragraph(CardPaymentStrings.text({
              'failed',
              'suppressed',
              'dead',
              'invalid_email'
            }.contains(delivery)
                ? 'emailFailed'
                : {'accepted', 'delivered'}.contains(delivery)
                    ? 'emailAccepted'
                    : delivery == 'not_requested'
                        ? 'emailNotRequested'
                        : 'emailPending')),
          if (!_uncertain && CardPaymentStatus.canContinue(payment))
            if (onPay != null)
              FilledButton(
                  onPressed: _busy ? null : _pay,
                  child: Text(CardPaymentStrings.text(
                      _busy ? 'preparing' : 'continuePayment')))
            else
              paragraph(CardPaymentStrings.text('protectedPaymentLink')),
          if (!CardPaymentStatus.canContinue(payment) &&
              {'open', 'declined'}.contains(state))
            paragraph(CardPaymentStrings.text('protectedPaymentLink')),
          if (onRefresh != null)
            TextButton(
                onPressed: onRefresh,
                child: Text(CardPaymentStrings.text('refresh'))),
        ]);
  }
}
