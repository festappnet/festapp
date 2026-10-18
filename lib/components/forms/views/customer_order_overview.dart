import '../models/verified_organization_identity.dart';
import '../widgets_view/organization_identity_footer.dart';
import '../order_overview_strings.dart';
import 'package:flutter/material.dart';
import 'package:festapp_core/forms.dart';

class CustomerOrderOverviewView extends StatefulWidget {
  const CustomerOrderOverviewView(
      {super.key,
      required this.load,
      this.onContinue,
      this.offerInPage = false});
  final Future<CustomerOrderOverview> Function() load;
  final VoidCallback? onContinue;
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

  String text(String key) => OrderOverviewStrings.text(key);
  String money(dynamic value, dynamic currency) =>
      value == null ? text('unknown') : '$value ${currency ?? ''}';
  Widget paragraph(String value) => Padding(
      padding: const EdgeInsets.symmetric(vertical: 4), child: Text(value));
  @override
  Widget build(BuildContext context) {
    if (_busy)
      return Semantics(
          label: text('loading'),
          child: const Center(child: CircularProgressIndicator()));
    if (_failed)
      return Column(children: [
        Semantics(liveRegion: true, child: Text(text('failed'))),
        TextButton(onPressed: _refresh, child: Text(text('refresh'))),
      ]);
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
                          style: Theme.of(context).textTheme.headlineSmall),
                      paragraph(
                          '${text('updated')}: ${data.data['serverTime']}'),
                      Align(
                          alignment: Alignment.centerLeft,
                          child: TextButton(
                              onPressed: _refresh,
                              child: Text(text('refresh')))),
                      Text(text('people'),
                          style: Theme.of(context).textTheme.titleLarge),
                      for (final person in data.people)
                        paragraph(
                            '${person['label'] ?? '#${person['id']}'} - ${text(person['effectiveLifecycle'])}'),
                      for (final offer in data.offers)
                        paragraph(
                            '${text(offer['effectiveStatus'])}: ${offer['pendingPlaces']} - ${offer['expiresAt']}'),
                      if (data.hasPendingOffer && widget.onContinue != null)
                        TextButton(
                            onPressed: widget.onContinue,
                            child: Text(text('continue')))
                      else if (data.hasPendingOffer && !widget.offerInPage)
                        paragraph(text('offerEmail')),
                      for (final order in data.orders)
                        Card(
                            child: Padding(
                                padding: const EdgeInsets.all(16),
                                child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.stretch,
                                    children: [
                                      Text(order['symbol'],
                                          style: Theme.of(context)
                                              .textTheme
                                              .titleLarge),
                                      paragraph(
                                          '${text('orderState')}: ${text(order['state'] ?? 'unknown')}'),
                                      paragraph(
                                          '${text('total')}: ${money(order['total'], order['currency'])}'),
                                      for (final item in order['items'] ?? [])
                                        paragraph(
                                            '${item['title'] ?? ''}: ${money(item['price'], item['currency'])}'),
                                      if (order['payment'] != null)
                                        ..._payment(order['payment'] as Map,
                                            order['currency']),
                                      for (final ticket
                                          in data.root['hasTickets'] == false
                                              ? []
                                              : order['tickets'])
                                        paragraph(
                                            '${ticket['label'] ?? '#${ticket['id']}'} - ${text(ticket['displayStatus'])}'),
                                    ]))),
                      if (!widget.offerInPage)
                        OrganizationIdentityFooter(
                            identity: VerifiedOrganizationIdentity.tryParse(
                                data.data['organizationIdentity'])),
                    ]))));
  }

  List<Widget> _payment(Map payment, dynamic currency) => [
        Text(text(payment['status']),
            style: Theme.of(context).textTheme.titleMedium),
        for (final key in [
          'received',
          'totalOutstanding',
          'returned',
          'overpaid'
        ])
          paragraph('${text(key)}: ${money(payment[key], currency)}'),
        if (payment['instructionsAvailable'] == true) ...[
          paragraph('${text('dueNow')}: ${money(payment['dueNow'], currency)}'),
          paragraph('${text('dueAt')}: ${payment['dueAt'] ?? text('onSite')}'),
          if (payment['overdue'] == true) paragraph(text('overdue')),
          paragraph('${text('account')}: ${payment['publicAccount']}'),
          paragraph('${payment['referenceKind']}: ${payment['reference']}'),
        ],
      ];
}
