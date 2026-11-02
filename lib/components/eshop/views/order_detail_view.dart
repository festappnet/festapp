import 'package:flutter/services.dart';
import 'package:easy_localization/easy_localization.dart';

import '../order_detail_strings.dart';

import 'package:fstapp/widgets/info_tooltip_button.dart';

import 'package:material_ui/material_ui.dart';
import 'package:file_saver/file_saver.dart';
import 'package:fstapp/widgets/app_dialog.dart';
import 'package:fstapp/services/exception_handler.dart';
import 'package:fstapp/services/launch_url_service.dart';
import 'package:fstapp/services/locale_date_time.dart';
import 'package:fstapp/services/utilities_all.dart';
import 'package:fstapp/data_services/rights_service.dart';
import 'package:festapp_core/forms.dart';

import '../../_shared/copy_button.dart';
import '../../_shared/common_strings.dart';
import '../../single_data_grid/data_grid_strings.dart';
import '../../email_delivery/email_delivery_history.dart';
import '../../email_delivery/order_email_issue.dart';
import '../../forms/waitlist_commands.dart';
import '../../forms/widgets_view/card_payment_status.dart';
import '../../features/feature_service.dart';
import '../../features/feature_constants.dart';
import '../models/order_admin_detail.dart';
import '../models/order_model.dart';
import '../order_detail_controller.dart';
import '../db_orders.dart';
import '../order_cancel_confirmation.dart';
import '../db_tickets.dart';
import 'order_email_repair_dialog.dart';
import 'order_history_dialog.dart';
import 'transactions_dialog.dart';
import 'products_dialog.dart';
import 'waitlist_order_detail.dart';
import 'order_places_view.dart';
import 'inline_order_field.dart';

import 'package:collection/collection.dart';

import 'order_detail_answers.dart';

class _CloseOrderDetailIntent extends Intent {
  const _CloseOrderDetailIntent();
}

const orderDetailTabs = [
  'overview',
  'tickets',
  'payments',
  'emails',
  'history',
];
List<String> get orderDetailTabLabels => [
  OrderDetailStrings.text('prehled'),
  OrderDetailStrings.text(
    FeatureService.isFeatureEnabled(FeatureConstants.ticket)
        ? 'vstupenky_a_mista'
        : 'applications_places',
  ),
  OrderDetailStrings.text('platby'),
  OrderDetailStrings.text('emaily'),
  OrderDetailStrings.text('historie'),
];

class OrderDetailView extends StatefulWidget {
  OrderDetailView({
    super.key,
    required this.controller,
    required this.tab,
    required this.onTab,
    required this.onClose,
    required this.onChanged,
    this.onPrevious,
    this.onNext,
    this.outsideFilter = false,
    this.formCount = 1,
    this.messageId,
    this.ticketId,
    this.onTicket,
    this.onReveal,
  });
  final OrderDetailController controller;
  final String tab;
  final ValueChanged<String> onTab;
  final Future<void> Function() onClose;
  final bool outsideFilter;
  final int formCount;
  final Future<void> Function() onChanged;
  final VoidCallback? onPrevious, onNext;
  final String? messageId;
  final int? ticketId;
  final ValueChanged<int?>? onTicket;
  final VoidCallback? onReveal;
  @override
  State<OrderDetailView> createState() => _OrderDetailViewState();
}

class _OrderDetailViewState extends State<OrderDetailView>
    with SingleTickerProviderStateMixin {
  final _visited = <int>{0};
  late final TabController _tabController;

  int get _tabIndex {
    final index = orderDetailTabs.indexOf(widget.tab);
    return index < 0 ? 0 : index;
  }

  @override
  void initState() {
    super.initState();
    _tabController = TabController(
      length: orderDetailTabs.length,
      vsync: this,
      initialIndex: _tabIndex,
    );
  }

  @override
  void didUpdateWidget(covariant OrderDetailView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (_tabController.index != _tabIndex) _tabController.index = _tabIndex;
  }

  bool _editingContact = false;
  bool _savingDrafts = false;
  String? _draftSaveError;
  int _revision = 0;
  final _placesKey = GlobalKey();
  final _ticketControllers = <int, ExpansibleController>{};
  final _ticketKeys = <int, GlobalKey>{};
  Set<int> _areaTickets = {};
  Set<int> _selectedTickets = {};
  int _selectionRevision = 0;
  @override
  void dispose() {
    _tabController.dispose();
    for (final controller in _ticketControllers.values) controller.dispose();
    super.dispose();
  }

  void _revealMapTickets(Set<int> ids) {
    if (ids.isEmpty) return;
    final revision = ++_selectionRevision;
    setState(() {
      _selectedTickets = Set.of(ids);
      _areaTickets = ids.length > 1 ? Set.of(ids) : {};
    });
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      if (!mounted || revision != _selectionRevision) return;
      for (final id in ids) _ticketControllers[id]?.expand();
      // Wait for expanded content to lay out before calculating its scroll offset.
      await Future<void>.delayed(const Duration(milliseconds: 250));
      if (!mounted || revision != _selectionRevision || c.detail == null)
        return;
      final first = d.tickets
          .where((ticket) => ids.contains(ticket['id']))
          .firstOrNull;
      final target = _ticketKeys[first?['id']]?.currentContext;
      if (target != null) {
        await Scrollable.ensureVisible(
          target,
          duration: const Duration(milliseconds: 180),
          alignment: .15,
        );
      }
    });
  }

  bool _ticketSelected(int id) =>
      _selectedTickets.contains(id) ||
      (_selectedTickets.isEmpty && widget.ticketId == id);

  Widget _ticketPresentation(Map<String, dynamic> ticket, Widget child) {
    final theme = Theme.of(context);
    final selected = _ticketSelected(ticket['id'] as int);
    return Semantics(
      key: ValueKey('ticket-selection-${ticket['id']}'),
      selected: selected,
      child: Padding(
        padding: const EdgeInsets.only(top: 8),
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: selected
                ? theme.colorScheme.primary.withValues(alpha: .045)
                : null,
            border: Border(
              bottom: BorderSide(
                color: selected
                    ? theme.colorScheme.primary
                    : theme.colorScheme.outlineVariant,
              ),
            ),
          ),
          child: Theme(
            data: theme.copyWith(
              hoverColor: theme.colorScheme.primary.withValues(alpha: .035),
              focusColor: theme.colorScheme.primary.withValues(alpha: .08),
            ),
            child: child,
          ),
        ),
      ),
    );
  }

  OrderDetailController get c => widget.controller;
  OrderAdminDetail get d => c.detail!;
  Future<void> _refresh({bool contact = false}) async {
    final ok = await c.load(acceptSavedContact: contact);
    if (mounted) setState(() => _revision++);
    try {
      await widget.onChanged();
    } catch (_) {
      /* persisted command remains confirmed */
    }
    if (!ok) throw StateError('Confirmed operation; refresh unavailable');
  }

  String money(dynamic value) => value == null
      ? OrderDetailStrings.text('nezname')
      : Utilities.formatPrice(
          context,
          num.parse(value.toString()).toDouble(),
          currencyCode: d.order['currency_code'] ?? 'CZK',
          decimalDigits: null,
        );
  Widget section(String title, Widget child) => Padding(
    padding: EdgeInsets.only(bottom: 24),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(title, style: Theme.of(context).textTheme.titleMedium),
        SizedBox(height: 10),
        child,
      ],
    ),
  );
  Widget _contact() => section(
    OrderDetailStrings.text('kontakt_zakaznika'),
    Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SelectableText(
          [
            d.order['data']?['name'],
            d.order['data']?['surname'],
          ].whereType<String>().join(' '),
          style: Theme.of(context).textTheme.titleMedium,
        ),
        SizedBox(height: 4),
        Row(
          children: [
            Expanded(
              child: SelectableText(
                d.order['data']?['email'] ??
                    OrderDetailStrings.text('email_missing'),
              ),
            ),
            if (!_editingContact &&
                widget.tab != 'emails' &&
                d.canWrite &&
                d.model.allows('edit'))
              IconButton(
                tooltip: OrderDetailStrings.text('edit_email'),
                onPressed: c.busy || c.stale
                    ? null
                    : () => setState(() => _editingContact = true),
                icon: const Icon(Icons.edit_outlined, size: 18),
              ),
          ],
        ),
        if (d.order['data']?['phone'] != null)
          SelectableText('${d.order['data']['phone']}'),
        if (_editingContact || widget.tab == 'emails')
          OrderEmailContactEditor(
            orderId: c.orderId,
            occasionId: c.occasionId,
            emailController: c.email,
            revision: _revision,
            canWrite: !c.stale && d.canWrite && d.model.allows('edit'),
            sourceMessageId: widget.messageId,
            onBusyChanged: c.setBusy,
            externalBusy: c.busy,
            showSaveOnlyAction: false,
            loadContext: () async => {
              'order': d.order,
              'emailSummary': d.emailSummary,
            },
            onChanged: () => _refresh(contact: true),
            onConflict: () => _refresh(),
          ),
      ],
    ),
  );
  Widget _financial() => section(
    OrderDetailStrings.text('platebni_prehled'),
    Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (d.payment['status'] == 'unknown')
          Text(OrderDetailStrings.text('platebni_stav_nelze_spolehlive_urcit')),
        for (final entry in {
          OrderDetailStrings.text('celkem'): d.order['price'],
          OrderDetailStrings.text('prijato'): d.payment['received'],
          OrderDetailStrings.text('vraceno'): d.payment['returned'],
          OrderDetailStrings.text('zbyva_k_uhrade'):
              d.payment['totalOutstanding'],
          OrderDetailStrings.text('aktualne_k_uhrade'): d.payment['dueNow'],
          if (d.payment['overpaid'] != null &&
              num.parse('${d.payment['overpaid']}') > 0)
            OrderDetailStrings.text('preplatek'): d.payment['overpaid'],
        }.entries)
          Padding(
            padding: EdgeInsets.only(bottom: 6),
            child: Row(
              children: [
                Expanded(child: Text(entry.key)),
                Text(
                  money(entry.value),
                  style: Theme.of(context).textTheme.titleSmall,
                ),
              ],
            ),
          ),
        if (d.payment['depositAmount'] != null &&
            num.parse('${d.payment['depositAmount']}') > 0) ...[
          Text(
            '${OrderDetailStrings.text('deposit')}: ${money(d.payment['depositAmount'])}',
          ),
          if (d.payment['depositDeadline'] != null)
            Text(
              '${OrderDetailStrings.text('deposit_due')}: ${_date(d.payment['depositDeadline'])}',
            ),
          if (d.payment['finalDeadline'] != null)
            Text(
              '${OrderDetailStrings.text('balance_due')}: ${_date(d.payment['finalDeadline'])}',
            ),
        ],
      ],
    ),
  );
  String _date(dynamic value) =>
      LocaleDateTime.instant(value, Localizations.localeOf(context).toString());
  bool get _issuesTickets =>
      FeatureService.isFeatureEnabled(FeatureConstants.ticket) &&
      d.fields
              .where((f) => f.type == FormMetadata.fieldTypeTicket)
              .firstOrNull
              ?.isHidden !=
          true;

  bool get _singleApplication {
    final container = d.fields
        .where((f) => f.type == FormMetadata.fieldTypeTicket)
        .firstOrNull;
    final maximum =
        int.tryParse('${container?.data?[FormMetadata.maxTickets] ?? 1}') ?? 1;
    return !_issuesTickets && maximum == 1 && d.tickets.length == 1;
  }

  bool _canEditProducts(Map<String, dynamic> ticket) =>
      !c.stale &&
      !c.busy &&
      d.canWrite &&
      d.model.allows('edit') &&
      ticket['batch'] == null &&
      ticket['state'] != 'used' &&
      ticket['state'] != 'storno' &&
      ticket['state'] != 'waitlisted' &&
      ticket['admission']?['reason'] != 'ADMISSION_DATA_AMBIGUOUS' &&
      !d.places.any(
        (p) => p['ticketId'] == ticket['id'] && p['problem'] != null,
      );

  Widget _editProductsButton(Map<String, dynamic> ticket) => TextButton.icon(
    icon: const Icon(Icons.edit_outlined, size: 18),
    label: Text(OrderDetailStrings.text('edit_products')),
    onPressed: () => ExceptionHandler.guard(
      context,
      futureFunction: () async {
        await showDialog<void>(
          context: context,
          builder: (_) => ProductsDialog(ticketId: ticket['id'] as int),
        );
        await _refresh();
      },
    ),
  );

  Widget _contents() => section(
    OrderDetailStrings.text('contents'),
    Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (d.tickets.isEmpty) Text(OrderDetailStrings.text('contents_empty')),
        for (final ticket in d.tickets)
          Padding(
            padding: const EdgeInsets.only(bottom: 16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (!_singleApplication)
                  Text(
                    [
                      ticket['ticket_symbol'] ??
                          '${OrderDetailStrings.text(_issuesTickets ? 'ticket' : 'application')} ${ticket['id']}',
                    ].where((v) => v.isNotEmpty).join(' · '),
                    style: Theme.of(context).textTheme.titleSmall,
                  ),
                if (detailRows(ticket['snapshot']?['products']).isEmpty)
                  Text(OrderDetailStrings.text('products_missing')),
                for (final product in detailRows(
                  ticket['snapshot']?['products'],
                ))
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    dense: true,
                    title: Text(product['title'] ?? ''),
                    trailing: Text(money(product['price'])),
                  ),
                if (_canEditProducts(ticket)) _editProductsButton(ticket),
              ],
            ),
          ),
      ],
    ),
  );

  bool _canEditAnswers() =>
      !c.stale &&
      c.validContext &&
      d.canWrite &&
      d.model.allows('edit') &&
      (d.json['form']?['id'] ?? d.order['form_id']) is int;

  Widget _answersView() {
    final orderId = c.orderId;
    return OrderDetailAnswers(
      detail: d,
      controller: c,
      canEdit: () =>
          c.detail != null && c.orderId == orderId && _canEditAnswers(),
      onSave: (fieldId, value, expectedFields) async {
        if (c.detail == null || c.orderId != orderId || !_canEditAnswers()) {
          throw StateError(OrderDetailStrings.text('responses_unavailable'));
        }
        final currentFields = d.json['answers'];
        final original = {for (final row in detailRows(expectedFields)) ...row};
        final current = {for (final row in detailRows(currentFields)) ...row};
        // Other saved fields may safely advance the array; this field may not.
        if (!const DeepCollectionEquality().equals(
          original['$fieldId'],
          current['$fieldId'],
        )) {
          throw StateError(OrderDetailStrings.text('responses_changed'));
        }
        await DbOrders.updateOrderDetailResponses(
          orderId: orderId,
          formId: (d.json['form']?['id'] ?? d.order['form_id']) as int,
          expectedFields: currentFields,
          responses: {'$fieldId': value},
        );
      },
    );
  }

  Future<void> _saveAllDrafts() async {
    if (c.busy || c.stale || _savingDrafts) return;
    final pendingCount = c.dirtyDraftCount;
    setState(() {
      _savingDrafts = true;
      _draftSaveError = null;
    });
    try {
      await c.saveDrafts();
      if (mounted) setState(() => _revision++);
      try {
        await widget.onChanged();
      } catch (_) {}
    } catch (error) {
      if (mounted)
        setState(() {
          final message = error is StateError
              ? error.message.toString()
              : OrderDetailStrings.text('responses_unavailable');
          _revision++;
          _draftSaveError = c.dirtyDraftCount == 0 && pendingCount > 0
              ? OrderDetailStrings.text('changes_saved_refresh_failed')
              : pendingCount > c.dirtyDraftCount
              ? '${OrderDetailStrings.text('changes_partially_saved')} $message'
              : message;
        });
      // Confirmed fields are already clean; remaining drafts keep their input.
      try {
        await widget.onChanged();
      } catch (_) {}
    } finally {
      if (mounted) setState(() => _savingDrafts = false);
    }
  }

  Widget _draftActions() => Material(
    color: Theme.of(context).colorScheme.surfaceContainerLow,
    child: Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Wrap(
            spacing: 8,
            runSpacing: 4,
            children: [
              FilledButton.icon(
                onPressed:
                    c.busy || c.stale || _savingDrafts || c.dirtyDraftCount == 0
                    ? null
                    : _saveAllDrafts,
                icon: _savingDrafts
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.save_outlined, size: 18),
                label: Text(CommonStrings.saveChanges),
              ),
              TextButton(
                onPressed: c.busy || _savingDrafts
                    ? null
                    : () {
                        c.discardDraft();
                        setState(() => _draftSaveError = null);
                      },
                child: Text(DataGridStrings.discardChanges),
              ),
            ],
          ),
          if (_draftSaveError != null)
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: Text(
                _draftSaveError!,
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
            ),
        ],
      ),
    ),
  );

  Widget _overview() {
    final issues = OrderEmailIssue.fromSummary(d.emailSummary);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (final issue in issues.take(2))
          ListTile(
            contentPadding: EdgeInsets.zero,
            leading: Icon(Icons.mark_email_unread_outlined),
            title: Text(issue.description),
            onTap: () => widget.onTab('emails'),
          ),
        if (d.payment['overdue'] == true)
          TextButton(
            onPressed: () => widget.onTab('payments'),
            child: Text(OrderDetailStrings.text('payment_overdue')),
          ),
        if (widget.formCount > 1)
          Padding(
            padding: const EdgeInsets.only(bottom: 16),
            child: Text(
              '${OrderDetailStrings.text('source_form')}: ${d.json['form']?['title'] ?? OrderDetailStrings.text('form_field')} · #${d.json['form']?['id'] ?? d.order['form_id'] ?? '-'}',
              style: Theme.of(context).textTheme.labelLarge,
            ),
          ),
        _contact(),
        InlineOrderField(
          key: ValueKey(('hidden-note', c.orderId)),
          label: 'OrderGridColumns.hiddenNote'.tr(),
          alwaysEditable: true,
          value: d.order['note_hidden']?.toString() ?? '',
          displayValue: d.order['note_hidden']?.toString().isNotEmpty == true
              ? d.order['note_hidden'].toString()
              : OrderDetailStrings.text('bez_poznamky'),
          controller: c,
          multiline: true,
          canEdit: () =>
              c.detail != null &&
              c.validContext &&
              !c.stale &&
              d.canWrite &&
              d.model.allows('note'),
          onSave: (value, _) async {
            if (!c.validContext ||
                c.stale ||
                !d.canWrite ||
                !d.model.allows('note'))
              throw StateError(
                OrderDetailStrings.text('responses_unavailable'),
              );
            await DbOrders.updateOrderNoteHidden(c.orderId, value);
          },
        ),
        _financial(),
        _contents(),
        Text(
          '${OrderDetailStrings.count(_issuesTickets ? 'tickets_count' : 'applications_count', d.tickets.length)} · ${OrderDetailStrings.count('places_count', d.places.where((p) => p['active'] == true && p['standing'] != true).map((p) => '${p['blueprintId']}:${p['spotId']}').toSet().length)}',
        ),
        Wrap(
          spacing: 8,
          children: [
            TextButton(
              onPressed: () => widget.onTab('tickets'),
              child: Text(
                OrderDetailStrings.text(
                  _issuesTickets ? 'vstupenky_a_mista' : 'applications_places',
                ),
              ),
            ),
            TextButton(
              onPressed: () => widget.onTab('payments'),
              child: Text(OrderDetailStrings.text('payment_details')),
            ),
            TextButton(
              onPressed: () => widget.onTab('emails'),
              child: Text(OrderDetailStrings.text('view_emails')),
            ),
          ],
        ),
        if (d.order['data']?['note'] != null)
          section(
            OrderDetailStrings.text('poznamka_zakaznika'),
            SelectableText('${d.order['data']['note']}'),
          ),
        ExpansionTile(
          key: PageStorageKey(('order-answers', c.orderId)),
          initiallyExpanded: true,
          tilePadding: EdgeInsets.zero,
          title: Text(OrderDetailStrings.text('udaje_z_formulare')),
          children: [
            KeyedSubtree(
              key: const PageStorageKey('answers-content'),
              child: _answersView(),
            ),
          ],
        ),
      ],
    );
  }

  Widget _tickets() => LayoutBuilder(
    builder: (context, constraints) {
      final sideBySide = constraints.maxWidth >= 1000;
      final map = OrderPlacesView(
        key: _placesKey,
        controller: c,
        ticketId: _selectedTickets.length == 1
            ? _selectedTickets.single
            : widget.ticketId,
        onTicket: widget.onTicket,
        onMapTickets: _revealMapTickets,
      );
      return Flex(
        direction: sideBySide ? Axis.horizontal : Axis.vertical,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (sideBySide)
            Expanded(child: map)
          else
            SizedBox(width: constraints.maxWidth, child: map),
          if (sideBySide)
            const SizedBox(width: 24)
          else
            const SizedBox(height: 20),
          if (sideBySide)
            Expanded(child: _ticketList())
          else
            SizedBox(width: constraints.maxWidth, child: _ticketList()),
        ],
      );
    },
  );

  Widget _ticketList() => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text(
        OrderDetailStrings.count(
          _issuesTickets ? 'tickets_count' : 'applications_count',
          d.tickets.length,
        ),
        style: Theme.of(context).textTheme.titleMedium,
      ),
      if (_areaTickets.isNotEmpty ||
          _selectedTickets.isNotEmpty ||
          widget.ticketId != null)
        TextButton(
          onPressed: () {
            setState(() {
              _selectionRevision++;
              _areaTickets = {};
              _selectedTickets = {};
            });
            widget.onTicket?.call(null);
          },
          child: Text(OrderDetailStrings.text('all_entries')),
        ),
      for (final ticket in d.tickets.where(
        (t) => _areaTickets.isEmpty || _areaTickets.contains(t['id']),
      ))
        KeyedSubtree(
          key: PageStorageKey(('order-ticket', c.orderId, ticket['id'])),
          child: _ticketPresentation(
            ticket,
            ExpansionTile(
              key: _ticketKeys.putIfAbsent(
                ticket['id'] as int,
                () => GlobalKey(),
              ),
              controller: _ticketControllers.putIfAbsent(
                ticket['id'] as int,
                () => ExpansibleController(),
              ),
              initiallyExpanded:
                  _singleApplication || _ticketSelected(ticket['id'] as int),
              onExpansionChanged: (expanded) {
                final id = ticket['id'] as int;
                if (expanded && !_selectedTickets.contains(id)) {
                  setState(() => _selectedTickets = {id});
                  widget.onTicket?.call(id);
                }
              },
              backgroundColor: Colors.transparent,
              collapsedBackgroundColor: Colors.transparent,
              shape: const Border(),
              collapsedShape: const Border(),
              childrenPadding: const EdgeInsets.fromLTRB(12, 4, 12, 18),
              tilePadding: const EdgeInsets.symmetric(
                horizontal: 12,
                vertical: 4,
              ),
              leading: Icon(
                _issuesTickets
                    ? Icons.confirmation_number_outlined
                    : Icons.person_outline,
                color: _ticketSelected(ticket['id'] as int)
                    ? Theme.of(context).colorScheme.primary
                    : Theme.of(context).colorScheme.onSurfaceVariant,
                semanticLabel: _ticketSelected(ticket['id'] as int)
                    ? OrderDetailStrings.text('selected_entry')
                    : null,
              ),
              title: Text(
                [
                  ticket['ticket_symbol'] ??
                      '${OrderDetailStrings.text(_issuesTickets ? 'ticket' : 'application')} ${ticket['id']}',
                ].where((s) => s.isNotEmpty).join(' · '),
                style: Theme.of(context).textTheme.titleSmall,
              ),
              subtitle: Text(
                [
                  ticket['state'] == 'used'
                      ? OrderDetailStrings.text('pouzita')
                      : ticket['state'] == 'storno'
                      ? OrderDetailStrings.text('zrusena')
                      : ticket['state'] == 'waitlisted'
                      ? OrderDetailStrings.text('ceka_na_misto')
                      : OrderDetailStrings.text(
                          _issuesTickets
                              ? 'dosud_nepouzita'
                              : 'application_active',
                        ),
                  if (ticket['batch'] != null)
                    OrderDetailStrings.text('tistena_davka'),
                  ticket['admission']?['reason'],
                ].whereType<String>().join(' · '),
              ),
              children: [
                Column(
                  key: const PageStorageKey('ticket-content'),
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    for (final product in detailRows(
                      ticket['snapshot']?['products'],
                    ))
                      ListTile(
                        contentPadding: EdgeInsets.zero,
                        title: Text(product['title'] ?? ''),
                        trailing: Text(money(product['price'])),
                      ),
                    if ((_issuesTickets || d.plans.isNotEmpty) &&
                        !d.places.any(
                          (p) =>
                              p['ticketId'] == ticket['id'] &&
                              p['active'] == true,
                        ))
                      Text(
                        ticket['state'] == 'waitlisted'
                            ? OrderDetailStrings.text('place_pending')
                            : OrderDetailStrings.text('place_none'),
                      ),
                    if (ticket['note'] != null)
                      SelectableText('${ticket['note']}'),
                    if (ticket['note_hidden'] != null)
                      SelectableText(
                        '${OrderDetailStrings.text('interni_poznamka')}: ${ticket['note_hidden']}',
                      ),
                    Wrap(
                      spacing: 8,
                      children: [
                        if (_issuesTickets &&
                            const [
                              'paid',
                              'sent',
                              'used',
                            ].contains(ticket['state']) &&
                            ticket['batch'] == null)
                          TextButton.icon(
                            icon: Icon(Icons.download_outlined),
                            label: Text(
                              OrderDetailStrings.text('stahnout_pdf'),
                            ),
                            onPressed: () => ExceptionHandler.guard(
                              context,
                              futureFunction: () async {
                                final bytes = await DbTickets.downloadTicketPdf(
                                  ticket['id'] as int,
                                );
                                if (bytes == null)
                                  throw StateError('PDF unavailable');
                                await FileSaver.instance.saveFile(
                                  name: 'vstupenka-${ticket['ticket_symbol']}',
                                  bytes: bytes,
                                  fileExtension: 'pdf',
                                  mimeType: MimeType.pdf,
                                );
                              },
                            ),
                          ),
                        if (d.canWrite &&
                            d.model.allows('cancel') &&
                            ticket['state'] != 'used' &&
                            ticket['state'] != 'storno' &&
                            ticket['batch'] == null)
                          TextButton(
                            onPressed: () => ExceptionHandler.guard(
                              context,
                              futureFunction: () async {
                                final ok = await showDialog<bool>(
                                  context: context,
                                  builder: (dialogContext) => AppAlertDialog(
                                    title: Text(
                                      OrderDetailStrings.text(
                                        _issuesTickets
                                            ? 'cancel_ticket_question'
                                            : 'cancel_application_question',
                                      ),
                                    ),
                                    content: Text(
                                      OrderDetailStrings.text(
                                        'cancel_entry_hint',
                                      ),
                                    ),
                                    actions: [
                                      TextButton(
                                        onPressed: () =>
                                            Navigator.pop(dialogContext, false),
                                        child: Text(
                                          OrderDetailStrings.text('zpet'),
                                        ),
                                      ),
                                      FilledButton(
                                        onPressed: () =>
                                            Navigator.pop(dialogContext, true),
                                        child: Text(
                                          OrderDetailStrings.text(
                                            _issuesTickets
                                                ? 'cancel_ticket'
                                                : 'cancel_application',
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                );
                                if (ok != true) return;
                                c.setBusy(true);
                                try {
                                  await DbTickets.stornoTickets([
                                    ticket['id'] as int,
                                  ]);
                                  await _refresh();
                                } finally {
                                  c.setBusy(false);
                                }
                              },
                            ),
                            child: Text(
                              OrderDetailStrings.text(
                                _issuesTickets
                                    ? 'cancel_ticket'
                                    : 'cancel_application',
                              ),
                            ),
                          ),
                        if (_canEditProducts(ticket))
                          _editProductsButton(ticket),
                      ],
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
    ],
  );
  Widget _payments() => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      if (d.order['payment_method'] == 'stripe')
        CardPaymentStatus(payment: d.payment, onRefresh: () => c.load()),
      if (d.payment['status'] == 'unknown') _financial(),
      if (d.payment['publicAccount'] != null)
        SelectableText(
          '${OrderDetailStrings.text('account')}: ${d.payment['publicAccount']}',
        ),
      if (d.payment['reference'] != null)
        SelectableText(
          '${OrderDetailStrings.text('payment_reference')}: ${d.payment['reference']}',
        ),
      if (d.payment['dueAt'] != null)
        Text('${OrderDetailStrings.text('due')}: ${_date(d.payment['dueAt'])}'),
      SizedBox(height: 16),
      OrderPaymentsContent(
        key: ValueKey('payments-$_revision'),
        summary: d.payment['status'] == 'unknown' ? null : _financial(),
        orderId: c.orderId,
        orderSymbol: d.model.orderSymbol,
        unitId: RightsService.currentUnit()?.id,
        onChanged: _refresh,
      ),
    ],
  );
  Widget _emails() => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      _contact(),
      EmailDeliveryHistory(
        key: ValueKey('email-$_revision'),
        occasionId: c.occasionId,
        orderId: c.orderId,
        messageId: widget.messageId,
        embedded: true,
        compact: true,
      ),
      SizedBox(height: 16),
      Text(
        OrderDetailStrings.text(
          'doruceni_postovnimu_serveru_neoveruje_totoznost_ani_precteni_otevreni_a_kliknuti_mohou_vzniknout_automaticky',
        ),
      ),
      Row(
        children: [
          InfoTooltipButton(
            semanticLabel: OrderDetailStrings.text(
              'vyznam_stavu_a_diagnostiky',
            ),
            message: OrderDetailStrings.text('email_status_help'),
          ),
          Flexible(
            child: Text(
              OrderDetailStrings.text('vyznam_stavu_a_diagnostiky'),
              style: Theme.of(context).textTheme.labelLarge,
            ),
          ),
        ],
      ),
    ],
  );
  Future<void> _more(String action) async {
    if (action == 'overview') {
      await LaunchUrlService.openExternalUrlFrom(
        () => WaitlistCommands().adminOverviewUrl(c.orderId),
      );
      return;
    }
    if (action == 'waitlist') {
      await showDialog<void>(
        context: context,
        builder: (_) =>
            WaitlistOrderDetail(order: d.model, onChanged: _refresh),
      );
      return;
    }
    if (action == 'contract') {
      await ExceptionHandler.guard(
        context,
        futureFunction: () async {
          final bytes = await DbOrders.downloadContractPdf(c.orderId);
          if (bytes != null)
            await FileSaver.instance.saveFile(
              name: 'smlouva-${d.model.orderSymbol}',
              bytes: bytes,
              fileExtension: 'pdf',
              mimeType: MimeType.pdf,
            );
        },
      );
      return;
    }
    if (c.busy || c.stale || !d.canWrite || !d.model.allows('cancel')) return;
    final ok = await confirmOrderCancellation(context, [d.model]);
    if (ok != true ||
        !mounted ||
        c.detail == null ||
        c.busy ||
        c.stale ||
        !d.canWrite ||
        !d.model.allows('cancel'))
      return;
    c.setBusy(true);
    try {
      await DbOrders.stornoOrder(c.orderId);
      await _refresh();
    } finally {
      c.setBusy(false);
    }
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: c,
    builder: (context, _) {
      if (c.loading) return Center(child: CircularProgressIndicator());
      if (c.detail == null)
        return Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                c.error ?? OrderDetailStrings.text('objednavka_neni_dostupna'),
              ),
              TextButton(
                onPressed: () => c.load(),
                child: Text(OrderDetailStrings.text('obnovit')),
              ),
              TextButton(
                onPressed: widget.onClose,
                child: Text(OrderDetailStrings.text('zpet_na_objednavky')),
              ),
            ],
          ),
        );
      var index = orderDetailTabs.indexOf(widget.tab);
      if (index < 0) index = 0;
      _visited.add(index);
      return Shortcuts(
        shortcuts: const {
          SingleActivator(LogicalKeyboardKey.escape, includeRepeats: false):
              _CloseOrderDetailIntent(),
        },
        child: Actions(
          actions: {
            _CloseOrderDetailIntent: CallbackAction<_CloseOrderDetailIntent>(
              onInvoke: (_) => c.busy ? null : widget.onClose(),
            ),
          },
          child: Material(
            color: Theme.of(context).colorScheme.surface,
            child: SafeArea(
              child: Column(
                children: [
                  Padding(
                    padding: EdgeInsets.fromLTRB(16, 12, 8, 8),
                    child: LayoutBuilder(
                      builder: (context, headerConstraints) {
                        final color = OrderModel.singleDataGridStateToColor(
                          d.model.state ?? '',
                        ).withValues(alpha: 1);
                        final navigation = Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            IconButton(
                              tooltip: OrderDetailStrings.text(
                                'predchozi_objednavka',
                              ),
                              onPressed: c.busy ? null : widget.onPrevious,
                              icon: const Icon(Icons.chevron_left),
                            ),
                            IconButton(
                              tooltip: OrderDetailStrings.text(
                                'dalsi_objednavka',
                              ),
                              onPressed: c.busy ? null : widget.onNext,
                              icon: const Icon(Icons.chevron_right),
                            ),
                          ],
                        );
                        final moreActions = PopupMenuButton<String>(
                          tooltip: OrderDetailStrings.text('dalsi_akce'),
                          enabled: !c.busy,
                          onSelected: _more,
                          itemBuilder: (_) => [
                            if (d.model.isWaitlisted)
                              PopupMenuItem(
                                value: 'waitlist',
                                child: Text(
                                  OrderDetailStrings.text(
                                    'sprava_cekaci_listiny',
                                  ),
                                ),
                              ),
                            if (FeatureService.isFeatureEnabled(
                              FeatureConstants.contract,
                            ))
                              PopupMenuItem(
                                value: 'contract',
                                child: Text(
                                  OrderDetailStrings.text('stahnout_smlouvu'),
                                ),
                              ),
                          ],
                        );
                        return Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Row(
                                        children: [
                                          Flexible(
                                            child: Text(
                                              '${OrderDetailStrings.text('order')} ${d.model.orderSymbol ?? c.orderId}',
                                              style: Theme.of(context)
                                                  .textTheme
                                                  .titleLarge
                                                  ?.copyWith(
                                                    fontWeight: FontWeight.bold,
                                                  ),
                                            ),
                                          ),
                                          CopyButton(
                                            value:
                                                d.model.orderSymbol ??
                                                '${c.orderId}',
                                          ),
                                          IconButton(
                                            tooltip: OrderDetailStrings.text(
                                              'zakaznicky_prehled',
                                            ),
                                            onPressed: c.busy
                                                ? null
                                                : () => ExceptionHandler.guard(
                                                    context,
                                                    futureFunction: () =>
                                                        _more('overview'),
                                                  ),
                                            icon: const Icon(
                                              Icons.open_in_new,
                                              size: 18,
                                            ),
                                          ),
                                        ],
                                      ),
                                      Container(
                                        padding: const EdgeInsets.symmetric(
                                          horizontal: 10,
                                          vertical: 4,
                                        ),
                                        decoration: BoxDecoration(
                                          color: color,
                                          borderRadius: BorderRadius.circular(
                                            6,
                                          ),
                                        ),
                                        child: Text(
                                          d.model.stateLabel,
                                          style: Theme.of(context)
                                              .textTheme
                                              .labelLarge
                                              ?.copyWith(
                                                color:
                                                    color.computeLuminance() >
                                                        .35
                                                    ? Colors.black
                                                    : Colors.white,
                                              ),
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                                navigation,
                                IconButton(
                                  tooltip: OrderDetailStrings.text(
                                    'zpet_na_objednavky',
                                  ),
                                  onPressed: c.busy ? null : widget.onClose,
                                  icon: const Icon(Icons.close),
                                ),
                              ],
                            ),
                            if (d.model.isWaitlisted ||
                                FeatureService.isFeatureEnabled(
                                  FeatureConstants.contract,
                                ) ||
                                (d.canWrite && d.model.allows('cancel')))
                              Padding(
                                padding: const EdgeInsets.only(top: 8),
                                child: Align(
                                  alignment: Alignment.centerRight,
                                  child: Wrap(
                                    spacing: 16,
                                    runSpacing: 4,
                                    crossAxisAlignment:
                                        WrapCrossAlignment.center,
                                    children: [
                                      if (d.canWrite &&
                                          d.model.allows('cancel'))
                                        TextButton.icon(
                                          icon: const Icon(
                                            Icons.cancel_outlined,
                                            size: 18,
                                          ),
                                          label: Text(
                                            OrderDetailStrings.text(
                                              'zrusit_objednavku',
                                            ),
                                          ),
                                          style: TextButton.styleFrom(
                                            foregroundColor: Theme.of(context)
                                                .colorScheme
                                                .error,
                                          ),
                                          onPressed: c.busy || c.stale
                                              ? null
                                              : () => ExceptionHandler.guard(
                                                  context,
                                                  futureFunction: () =>
                                                      _more('cancel'),
                                                ),
                                        ),
                                      if (d.model.isWaitlisted ||
                                          FeatureService.isFeatureEnabled(
                                            FeatureConstants.contract,
                                          ))
                                        if (d.model.isWaitlisted ||
                                            FeatureService.isFeatureEnabled(
                                              FeatureConstants.contract,
                                            ))
                                          moreActions,
                                    ],
                                  ),
                                ),
                              ),
                          ],
                        );
                      },
                    ),
                  ),
                  if (widget.outsideFilter)
                    Padding(
                      padding: EdgeInsets.all(8),
                      child: Text(
                        OrderDetailStrings.text(
                          'tato_objednavka_neodpovida_aktualnim_filtrum',
                        ),
                      ),
                    ),
                  if (widget.outsideFilter && widget.onReveal != null)
                    TextButton(
                      onPressed: widget.onReveal,
                      child: Text(OrderDetailStrings.text('reveal_row')),
                    ),
                  if (c.stale)
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            c.error ??
                                OrderDetailStrings.text(
                                  'udaje_nejsou_aktualni',
                                ),
                          ),
                        ),
                        TextButton(
                          onPressed: () => c.load(),
                          child: Text(OrderDetailStrings.text('obnovit')),
                        ),
                      ],
                    ),
                  TabBar(
                    controller: _tabController,
                    isScrollable: true,
                    tabAlignment: TabAlignment.start,
                    onTap: (i) => widget.onTab(orderDetailTabs[i]),
                    tabs: [
                      for (var i = 0; i < orderDetailTabs.length; i++)
                        Tab(
                          text: i == 1
                              ? OrderDetailStrings.text(
                                  _issuesTickets
                                      ? 'vstupenky_a_mista'
                                      : 'applications_places',
                                )
                              : orderDetailTabLabels[i],
                        ),
                    ],
                  ),
                  if (c.dirtyDraftCount > 0 ||
                      _savingDrafts ||
                      _draftSaveError != null)
                    _draftActions(),
                  Expanded(
                    child: IndexedStack(
                      index: index,
                      children: [
                        for (var i = 0; i < 5; i++)
                          _visited.contains(i)
                              ? SingleChildScrollView(
                                  // Expansion tiles below this scroller own distinct PageStorageKeys.
                                  key: PageStorageKey('order-${c.orderId}-$i'),
                                  padding: EdgeInsets.all(20),
                                  child: switch (i) {
                                    0 => _overview(),
                                    1 => _tickets(),
                                    2 => _payments(),
                                    3 => _emails(),
                                    _ => OrderHistoryContent(
                                      key: ValueKey('history-$_revision'),
                                      orderId: c.orderId,
                                    ),
                                  },
                                )
                              : SizedBox.shrink(),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      );
    },
  );
}
