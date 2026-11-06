import '../../forms/payment_method_strings.dart';
import 'package:material_ui/material_ui.dart';

import '../../../services/payment_deadline.dart';
import '../../../services/utilities_all.dart';
import '../../../theme_config.dart';
import '../../forms/card_payment_strings.dart';
import '../../forms/order_overview_strings.dart';
import '../../forms/widgets_view/card_payment_status.dart';
import '../order_detail_strings.dart';
import '../orders_strings.dart';

/// Compact presentation of server financial facts; never recalculates a balance.
class OrderPaymentSummary extends StatelessWidget {
  const OrderPaymentSummary({
    super.key,
    required this.payment,
    required this.total,
    required this.currencyCode,
    this.isCard = false,
    this.onOverdueTap,
  });

  final Map<String, dynamic> payment;
  final dynamic total;
  final String currencyCode;
  final bool isCard;
  final VoidCallback? onOverdueTap;

  num? _number(dynamic value) {
    final parsed = value is num ? value : num.tryParse('$value');
    return parsed?.isFinite == true ? parsed : null;
  }

  @override
  Widget build(BuildContext context) {
    String money(dynamic value) {
      final number = _number(value);
      if (number == null) return OrderDetailStrings.text('nezname');
      return Utilities.formatPrice(
        context,
        number.toDouble(),
        currencyCode: currencyCode,
        decimalDigits: isCard || number % 1 != 0 ? 2 : 0,
      );
    }

    final status = payment['status']?.toString() ?? 'unknown';
    final returned = _number(payment['returned']);
    final fullyPaid =
        const {'fully_paid', 'paid'}.contains(status) &&
        returned == 0 &&
        _number(payment['received']) != null &&
        _number(total) != null;
    final waiting = const {
      'unpaid',
      'partially_paid',
      'deposit_paid',
      'preparing',
      'open',
      'pending',
      'declined',
      'action_required',
      'refund_pending',
      'disputed',
    }.contains(status);
    final color = fullyPaid
        ? ThemeConfig.greenColor(context)
        : waiting
        ? ThemeConfig.warningColor(context)
        : null;
    final quietNoPayment =
        const {'free', 'not_required_yet'}.contains(status) &&
        _number(payment['received']) == 0 &&
        returned == 0;
    String? hint;
    if (status == 'unknown') {
      hint = OrderDetailStrings.text('platebni_stav_nelze_spolehlive_urcit');
    } else if (isCard &&
        status != 'paid' &&
        CardPaymentStatus.states.contains(status)) {
      hint = CardPaymentStrings.text(status);
    } else if (const {
      'cancelled',
      'free',
      'not_required_yet',
      'preparing',
    }.contains(status)) {
      hint = OrderOverviewStrings.text(status);
    }

    if (quietNoPayment) hint = null;
    Widget fact(String key, dynamic value) => Padding(
      padding: const EdgeInsets.only(top: 6),
      child: Row(
        children: [
          Expanded(child: Text(OrderDetailStrings.text(key))),
          Text(money(value), style: Theme.of(context).textTheme.titleSmall),
        ],
      ),
    );
    final showPaymentDue = status != 'cancelled';
    final outstanding = _number(payment['totalOutstanding']);
    final dueNow = _number(payment['dueNow']);
    return Padding(
      padding: const EdgeInsets.only(bottom: 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(
                OrdersStrings.infoPayment,
                style: Theme.of(context).textTheme.titleMedium,
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Tooltip(
                  message:
                      '${OrderDetailStrings.text('prijato')} / ${OrderDetailStrings.text('celkem')}',
                  child: SelectableText(
                    quietNoPayment
                        ? OrderOverviewStrings.text(status)
                        : '${money(payment['received'])} / ${money(total)}',
                    textAlign: TextAlign.right,
                    style: Theme.of(context).textTheme.titleMedium
                        ?.copyWith(fontWeight: FontWeight.bold, color: color),
                  ),
                ),
              ),
            ],
          ),
          OrderPaymentOverdueNotice(
            payment: payment,
            currencyCode: currencyCode,
            isCard: isCard,
            showDetails: false,
            onTap: onOverdueTap,
          ),
          if (payment['method'] == 'cash') ...[
            Text(PaymentMethodStrings.text('cash')),
            if (payment['instructionsAvailable'] == true)
              Text(payment['instructions']?['cashInstructions']?.toString().isNotEmpty == true
                ? payment['instructions']['cashInstructions'] as String
                : PaymentMethodStrings.text('cashInstructionsDefault')),
          ],
          if (hint != null)
            Padding(padding: const EdgeInsets.only(top: 6), child: Text(hint)),
          if (returned != null && returned > 0) fact('vraceno', returned),
          if (showPaymentDue && outstanding != null && outstanding > 0)
            fact('zbyva_k_uhrade', outstanding),
          if (showPaymentDue &&
              dueNow != null &&
              dueNow > 0 &&
              dueNow != outstanding)
            fact('aktualne_k_uhrade', dueNow),
          if (_number(payment['overpaid']) case final amount? when amount > 0)
            fact('preplatek', amount),
          if (showPaymentDue)
            if (_number(payment['depositAmount']) case final amount?
                when amount > 0) ...[
              fact('deposit', amount),
            ],
          if (showPaymentDue)
            for (final entry in {
              'depositDeadline': 'deposit_due',
              'finalDeadline': (_number(payment['depositAmount']) ?? 0) > 0
                  ? 'balance_due'
                  : 'payment_deadline',
            }.entries)
              if (payment[entry.key] != null)
                Padding(
                  padding: const EdgeInsets.only(top: 6),
                  child: Text(
                    '${entry.value == 'payment_deadline' ? OrderOverviewStrings.text('dueAt') : OrderDetailStrings.text(entry.value)}: ${PaymentDeadline.format(payment[entry.key], Localizations.localeOf(context).toString())}',
                  ),
                ),
        ],
      ),
    );
  }
}

/// Server-owned overdue state, shared by the overview and the payment tab.
class OrderPaymentOverdueNotice extends StatelessWidget {
  const OrderPaymentOverdueNotice({
    super.key,
    required this.payment,
    required this.currencyCode,
    this.isCard = false,
    this.showDetails = true,
    this.onTap,
  });

  final Map<String, dynamic> payment;
  final String currencyCode;
  final bool isCard;
  final bool showDetails;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    if (payment['overdue'] != true || payment['status'] == 'cancelled') {
      return const SizedBox.shrink();
    }
    final colors = Theme.of(context).colorScheme;
    num? number(dynamic value) {
      final parsed = value is num ? value : num.tryParse('$value');
      return parsed?.isFinite == true ? parsed : null;
    }

    String money(num value) => Utilities.formatPrice(
      context,
      value.toDouble(),
      currencyCode: currencyCode,
      decimalDigits: isCard || value % 1 != 0 ? 2 : 0,
    );
    final due = number(payment['dueNow']);
    final outstanding = number(payment['totalOutstanding']);
    final details = <String>[
      if (due != null && due > 0)
        '${OrderDetailStrings.text('aktualne_k_uhrade')}: ${money(due)}',
      if (outstanding != null && outstanding > 0 && outstanding != due)
        '${OrderDetailStrings.text('zbyva_k_uhrade')}: ${money(outstanding)}',
      if (payment['dueAt'] != null)
        '${OrderOverviewStrings.text('dueAt')}: ${PaymentDeadline.format(payment['dueAt'], Localizations.localeOf(context).toString())}',
    ];
    return Padding(
      padding: const EdgeInsets.only(top: 12, bottom: 12),
      child: Material(
        color: colors.errorContainer,
        borderRadius: BorderRadius.circular(8),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(
                  Icons.schedule_outlined,
                  size: 20,
                  color: colors.onErrorContainer,
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        OrderOverviewStrings.text('overdue'),
                        style: Theme.of(context).textTheme.titleSmall
                            ?.copyWith(color: colors.onErrorContainer),
                      ),
                      if (showDetails)
                        for (final line in details)
                          Padding(
                            padding: const EdgeInsets.only(top: 4),
                            child: Text(
                              line,
                              style: TextStyle(color: colors.onErrorContainer),
                            ),
                          ),
                    ],
                  ),
                ),
                if (onTap != null)
                  Icon(
                    Icons.chevron_right,
                    size: 20,
                    color: colors.onErrorContainer,
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
