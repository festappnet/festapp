import 'package:fstapp/components/_shared/common_strings.dart';
import 'package:fstapp/components/discount_codes/discount_summary.dart';

import '../customer_order_changes.dart';

import 'package:fstapp/components/discount_codes/discount_strings.dart';
import 'package:festapp_core/payments.dart';

import '../payment_method_strings.dart';
import '../models/verified_organization_identity.dart';
import '../widgets_view/organization_identity_footer.dart';
import '../order_overview_strings.dart';

import 'package:material_ui/material_ui.dart';
import 'package:festapp_core/forms.dart';

import '../widgets_view/card_payment_status.dart';

import 'package:easy_localization/easy_localization.dart';

class CustomerOrderOverviewView extends StatefulWidget {
  const CustomerOrderOverviewView({
    super.key,
    required this.load,
    this.onContinue,
    this.offerInPage = false,
    this.scope,
  });
  final Future<CustomerOrderOverview> Function() load;
  final VoidCallback? onContinue;
  final CustomerOrderScope? scope;
  final bool offerInPage;
  @override
  State<CustomerOrderOverviewView> createState() =>
      _CustomerOrderOverviewViewState();
}

class _CustomerOrderOverviewViewState extends State<CustomerOrderOverviewView> {
  CustomerOrderOverview? _data;
  bool _busy = true;
  bool _failed = false;
  int _generation = 0;
  @override
  void initState() {
    super.initState();
    _refresh();
  }

  @override
  void didUpdateWidget(CustomerOrderOverviewView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.key != widget.key) _refresh();
  }

  Future<void> _refresh() async {
    final generation = ++_generation;
    setState(() {
      _busy = true;
      _failed = false;
      _data = null;
    });
    try {
      final data = await widget.load();
      if (mounted && generation == _generation) setState(() => _data = data);
    } catch (_) {
      if (mounted && generation == _generation) setState(() => _failed = true);
    } finally {
      if (mounted && generation == _generation) setState(() => _busy = false);
    }
  }

  String? seatingText(Map item) {
    final standing = item['isStanding'] == true;
    final kind = standing ? 'standing' : item['spotGroupKind'];
    final raw = standing ? item['standingAreaTitle'] : item['spotGroupTitle'];
    final title = raw is String ? raw.trim() : '';
    final key = switch (kind) {
      'standing' => 'standingPlace',
      'table' => 'table',
      'couch' => 'couch',
      'row' => 'row',
      _ => RegExp(r'^\d+$').hasMatch(title) ? 'group' : null,
    };
    final label = key == null ? '' : text(key);
    final normalized = title.toLowerCase();
    final prefix = label.toLowerCase();
    final group = title.isEmpty ? label : label.isEmpty || normalized == prefix ||
        normalized.startsWith('$prefix ') || normalized.startsWith('$prefix:')
        ? title : '$label $title';
    final seat = standing ? '' : item['spotTitle']?.toString().trim() ?? '';
    final parts = [if (group.isNotEmpty) group, if (seat.isNotEmpty) '${text('seat')}: $seat'];
    return parts.isEmpty ? null : parts.join(' · ');
  }

  String text(String key) => OrderOverviewStrings.text(
    key,
    hasTickets: _data?.root['hasTickets'] == true,
  );
  String money(dynamic value, dynamic currency, {bool card = false}) => card
      ? CardPaymentStatus.formatMoney(
              value,
              currency,
              context.locale.toLanguageTag(),
            ) ??
            text('unknown')
      : value == null
      ? text('unknown')
      : '$value ${currency ?? ''}';
  Widget paragraph(String value) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 4),
    child: Text(value),
  );
  @override
  Widget build(BuildContext context) {
    if (_busy) {
      return Semantics(
        label: text('loading'),
        child: const Center(child: CircularProgressIndicator()),
      );
    }
    if (_failed) {
      return Column(
        children: [
          Semantics(liveRegion: true, child: Text(text('failed'))),
          TextButton(onPressed: _refresh, child: Text(CommonStrings.refresh)),
        ],
      );
    }
    final data = _data!;
    return Align(
      alignment: Alignment.topCenter,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 850),
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                '${data.root['title'] ?? ''} - ${data.root['symbol']}',
                style: Theme.of(context).textTheme.headlineSmall,
              ),
              paragraph('${text('updated')}: ${data.data['serverTime']}'),
              Align(
                alignment: Alignment.centerLeft,
                child: TextButton(
                  onPressed: _refresh,
                  child: Text(CommonStrings.refresh),
                ),
              ),
              if (widget.scope != null)
                CustomerOrderChanges(
                  scope: widget.scope!,
                  data: data,
                  onChanged: _refresh,
                ),
              Text(
                text('people'),
                style: Theme.of(context).textTheme.titleLarge,
              ),
              for (final person in data.people)
                paragraph(
                  '${person['label'] ?? '#${person['id']}'} - ${text(person['effectiveLifecycle'])}',
                ),
              for (final offer in data.offers)
                paragraph(
                  '${text(offer['effectiveStatus'])}: ${offer['pendingPlaces']} - ${offer['expiresAt']}',
                ),
              if (data.hasPendingOffer && widget.onContinue != null)
                TextButton(
                  onPressed: widget.onContinue,
                  child: Text(text('continue')),
                )
              else if (data.hasPendingOffer && !widget.offerInPage)
                paragraph(text('offerEmail')),
              for (final order in data.orders)
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Text(
                          order['symbol'],
                          style: Theme.of(context).textTheme.titleLarge,
                        ),
                        paragraph(
                          '${text('orderState')}: ${text(order['state'] ?? 'unknown')}',
                        ),
                        for (final item in order['items'] ?? []) ...[
                          paragraph(
                            '${item['title'] ?? ''}: ${order['discount'] != null ? formatDiscountPrice(context, (item['basePrice'] ?? item['price']) as num, item['currency'] ?? order['currency']) : money(item['price'], item['currency'])}',
                          ),
                          if (seatingText(item) case final String seating)
                            Text(
                              seating,
                              style: Theme.of(context).textTheme.bodyMedium
                                  ?.copyWith(fontWeight: FontWeight.w600),
                            ),
                        ],
                        if (order['discount'] != null) ...[
                          if (order['state'] == 'storno' ||
                              ((order['total'] as num) * 100).round() !=
                                  ((order['discount']['net'] as num) * 100)
                                      .round())
                            paragraph(DiscountStrings.text('originalSale')),
                          DiscountSummary(
                            discount: Map<String, dynamic>.from(
                              order['discount'] as Map,
                            ),
                          ),
                        ],
                        if (order['discount'] == null ||
                            order['state'] == 'storno' ||
                            ((order['total'] as num) * 100).round() !=
                                ((order['discount']['net'] as num) * 100)
                                    .round())
                          paragraph(
                            '${text('total')}: ${money(order['total'], order['currency'], card: paymentConnectors.containsHosted(order['payment']?['method']))}',
                          ),
                        if (order['payment'] != null)
                          ..._payment(
                            order['payment'] as Map,
                            order['currency'],
                          ),
                        for (final ticket
                            in data.root['hasTickets'] == false
                                ? []
                                : order['tickets'])
                          paragraph(
                            '${ticket['label'] ?? '#${ticket['id']}'} - ${text(ticket['displayStatus'])}',
                          ),
                      ],
                    ),
                  ),
                ),
              if (!widget.offerInPage)
                OrganizationIdentityFooter(
                  identity: VerifiedOrganizationIdentity.tryParse(
                    data.data['organizationIdentity'],
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  List<Widget> _payment(Map payment, dynamic currency) =>
      paymentConnectors.containsHosted(payment['method'])
      ? [
          CardPaymentStatus(
            hasTickets: _data?.root['hasTickets'] == true,
            payment: {...payment.cast<String, dynamic>(), 'currency': currency},
            onRefresh: _refresh,
          ),
        ]
      : [
          Text(
            text(payment['status']),
            style: Theme.of(context).textTheme.titleMedium,
          ),
          for (final key in [
            'received',
            if (payment['net'] != null) 'net',
            if ((num.tryParse('${payment['pending']}') ?? 0) > 0)
              'pendingRefund',
            'totalOutstanding',
            'returned',
            'overpaid',
          ])
            paragraph(
              '${text(key)}: ${money(payment[key == 'pendingRefund' ? 'pending' : key], currency)}',
            ),
          if (payment['instructionsAvailable'] == true) ...[
            paragraph(
              '${text('dueNow')}: ${money(payment['dueNow'], currency)}',
            ),
            if (payment['dueAt'] != null)
              paragraph('${text('dueAt')}: ${payment['dueAt']}'),
            if (payment['overdue'] == true) paragraph(text('overdue')),
            if (payment['method'] == 'cash') ...[
              paragraph(PaymentMethodStrings.text('payOnSite')),
              paragraph(
                payment['instructions']?['cashInstructions']
                            ?.toString()
                            .isNotEmpty ==
                        true
                    ? payment['instructions']['cashInstructions']
                    : PaymentMethodStrings.text('cashInstructionsDefault'),
              ),
            ] else ...[
              paragraph('${text('account')}: ${payment['publicAccount']}'),
              paragraph('${payment['referenceKind']}: ${payment['reference']}'),
            ],
          ],
        ];
}
