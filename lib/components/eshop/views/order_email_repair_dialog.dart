import 'dart:convert';

import 'package:festapp_core/forms.dart';
import 'package:material_ui/material_ui.dart';
import 'package:fstapp/components/_shared/common_strings.dart';
import 'package:fstapp/widgets/app_dialog.dart';
import 'package:fstapp/components/email_delivery/order_email_issue.dart';
import 'package:fstapp/components/email_delivery/email_delivery_strings.dart';
import 'package:fstapp/data_services/rights_service.dart';

import '../order_commands.dart';
import '../order_contact_controller.dart';

class OrderEmailContactEditor extends StatefulWidget {
  const OrderEmailContactEditor({
    super.key,
    required this.orderId,
    required this.occasionId,
    this.sourceMessageId,
    this.read,
    this.commands,
    this.canWrite,
    this.onChanged,
    this.controller,
    this.hostBuilder,
    this.showSaveOnlyAction = true,
    this.onShowOrder,
  });
  final Widget Function(Widget body, List<Widget> actions, bool busy)?
  hostBuilder;
  final OrderContactController? controller;
  final bool showSaveOnlyAction;
  final VoidCallback? onShowOrder;
  final int orderId;
  final int occasionId;
  final String? sourceMessageId;
  final Future<dynamic> Function(String, Map<String, dynamic>)? read;
  final OrderCommands? commands;
  final bool? canWrite;
  final Future<void> Function()? onChanged;
  @override
  State<OrderEmailContactEditor> createState() =>
      _OrderEmailContactEditorState();
}

class _OrderEmailContactEditorState extends State<OrderEmailContactEditor> {
  late OrderContactController _contact =
      widget.controller ??
      OrderContactController(
        orderId: widget.orderId,
        occasionId: widget.occasionId,
        read: widget.read,
        commands: widget.commands,
        onChanged: widget.onChanged,
      );
  final _emailFocus = FocusNode();
  bool _emailTouched = false;
  String? _selectedMessage;
  TextEditingController get _email => _contact.email;
  Map<String, dynamic>? get _order => _contact.order;
  Map<String, dynamic>? get _summary => _contact.summary;
  bool get _busy => _contact.busy;
  bool get _locked => _contact.busy || _contact.hostBusy;
  bool get _loading => _contact.loading;
  bool get _stale => _contact.stale;
  String? get _feedback => _contact.feedback;
  String t(String key) => EmailDeliveryStrings.recovery(key);
  void _changed() {
    if (mounted) setState(() {});
  }

  Future<void> _save(bool resend, OrderEmailIssue? issue) async {
    try {
      await _contact.save(resend: resend, issue: issue);
      if (mounted && widget.controller != null) await widget.onChanged?.call();
    } catch (_) {
      /* controller reports outcome */
    }
  }

  @override
  void initState() {
    super.initState();
    _contact.addListener(_changed);
    _emailFocus.addListener(() {
      if (mounted)
        setState(() {
          if (!_emailFocus.hasFocus) _emailTouched = true;
        });
    });
    if (widget.controller == null) _contact.load();
  }

  @override
  void didUpdateWidget(covariant OrderEmailContactEditor oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.controller == widget.controller && oldWidget.orderId == widget.orderId && oldWidget.occasionId == widget.occasionId) return;
    _contact.removeListener(_changed);
    if (oldWidget.controller == null) _contact.dispose();
    _contact = widget.controller ?? OrderContactController(
      orderId: widget.orderId, occasionId: widget.occasionId,
      read: widget.read, commands: widget.commands, onChanged: widget.onChanged,
    );
    _contact.addListener(_changed);
    _selectedMessage = null;
    _emailTouched = false;
    if (widget.controller == null) _contact.load();
  }

  Future<void> _recover() async {
    await _contact.recover();
    if (mounted && widget.controller != null) await widget.onChanged?.call();
  }

  @override
  void dispose() {
    _contact.removeListener(_changed);
    if (widget.controller == null) _contact.dispose();
    _emailFocus.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final issues = OrderEmailIssue.fromSummary(_summary);
    final currentKind = _order?['state'] == 'ordered'
        ? 'order_confirmation'
        : 'order_tickets';
    // The summary contains repair-chain leaves. An obsolete confirmation must
    // never become the source for sending tickets, nor bypass a current guard.
    final currentIssues = issues
        .where((i) => i.kind == currentKind && i.data['obsolete'] != true)
        .toList();
    final selected =
        currentIssues
            .where(
              (i) =>
                  i.messageId == (_selectedMessage ?? widget.sourceMessageId) ||
                  i.sourceId == (_selectedMessage ?? widget.sourceMessageId),
            )
            .firstOrNull ??
        (currentIssues.length == 1 ? currentIssues.single : null);
    final writable =
        !_stale &&
        (widget.canWrite ?? RightsService.canUpdateOrders()) &&
        const ['ordered', 'paid', 'sent'].contains(_order?['state']);
    final uncertain = issues.any((i) => i.uncertain);
    final recipientBlocked = issues.any((i) => i.blocksRecipient(_email.text));
    final ambiguous = currentIssues.length > 1 && selected == null;
    final sourceBlocked = selected != null && !selected.canResend;
    final storedEmail = _order?['data']['email']?.toString() ?? '';
    final changed = _email.text.trim() != storedEmail;
    final addressChanged =
        _email.text.trim().toLowerCase() != storedEmail.trim().toLowerCase();
    final recipientIssues = issues.where(
      (i) =>
          (i.data['recipient'] ?? i.originalRecipient)
              .toString()
              .trim()
              .toLowerCase() ==
          storedEmail.trim().toLowerCase(),
    );
    final complaint = recipientIssues.any(
      (i) =>
          i.state == 'complaint' || i.data['suppression_reason'] == 'complaint',
    );
    final addressProblem =
        !complaint &&
        recipientIssues.any(
          (i) =>
              i.state == 'bounce' ||
              i.data['suppression_reason'] == 'hard_bounce' ||
              i.blocksRecipient(storedEmail),
        );
    final addressMustChange = addressProblem && !addressChanged;
    final valid = EmailAddress.isValid(_email.text.trim());
    final theme = Theme.of(context);
    final secondaryStyle = theme.textTheme.bodyMedium?.copyWith(
      color: theme.colorScheme.onSurfaceVariant,
    );
    final sendLabel = t(
      currentKind == 'order_tickets'
          ? (changed || addressProblem ? 'saveSendTickets' : 'sendTickets')
          : (changed || addressProblem
                ? 'saveSendConfirmation'
                : 'sendConfirmation'),
    );
    final explanation = _order?['state'] == 'storno'
        ? t('cancelled')
        : uncertain
        ? t('uncertain')
        : !writable
        ? t('readonly')
        : complaint
        ? t('spam')
        : addressMustChange
        ? t('repairInstruction')
        : recipientBlocked
        ? t('blockedHint')
        : ambiguous
        ? t('chooseMessage')
        : sourceBlocked
        ? (selected.data['resolution'] == 'waiting_repair' ||
                  const {
                    'pending',
                    'preparing',
                    'blocked',
                  }.contains(selected.state)
              ? t('waiting')
              : t('reviewBlocked'))
        : addressProblem
        ? t('repairInstruction')
        : issues.isNotEmpty
        ? t('verifyInstruction')
        : null;

    final body = Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          t(addressProblem ? 'repairHeading' : 'heading'),
          style: theme.textTheme.titleMedium,
        ),
        const SizedBox(height: 12),
        if (_loading) const Center(child: CircularProgressIndicator()),
        if (_stale) Text(t('stale')),
        if (_order != null) ...[
          SelectableText(
            [
              [
                _order!['data']['name'],
                _order!['data']['surname'],
              ].whereType<String>().join(' '),
              if (_order!['order_symbol'] != null)
                '#${_order!['order_symbol']}',
            ].where((part) => part.isNotEmpty).join(' · '),
            style: secondaryStyle,
          ),
          const SizedBox(height: 20),
          if (issues.isNotEmpty || explanation != null) ...[
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(
                  uncertain ? Icons.schedule : Icons.mark_email_unread_outlined,
                  size: 22,
                  color: theme.colorScheme.error,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      if (explanation != null)
                        Text(explanation, style: theme.textTheme.bodyMedium),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 20),
          ],
          if (writable)
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(t('email'), style: theme.textTheme.labelMedium),
                const SizedBox(height: 6),
                DecoratedBox(
                  key: const ValueKey('order-email-field-frame'),
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(4),
                    border: Border.all(
                      color: _emailFocus.hasFocus
                          ? theme.colorScheme.primary
                          : theme.colorScheme.outline,
                    ),
                  ),
                  child: Semantics(
                    label: t('email'),
                    child: TextField(
                      controller: _email,
                      focusNode: _emailFocus,
                      onChanged: (_) => setState(() {}),
                      enabled: !_locked,
                      cursorOpacityAnimates: false,
                      keyboardType: TextInputType.emailAddress,
                      decoration: const InputDecoration(
                        contentPadding: EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 12,
                        ),
                        border: InputBorder.none,
                        enabledBorder: InputBorder.none,
                        focusedBorder: InputBorder.none,
                        disabledBorder: InputBorder.none,
                        filled: false,
                        hoverColor: Colors.transparent,
                        focusColor: Colors.transparent,
                      ),
                    ),
                  ),
                ),
                if (_emailTouched && !_emailFocus.hasFocus && !valid)
                  Padding(
                    padding: const EdgeInsets.only(top: 6),
                    child: Semantics(
                      liveRegion: true,
                      child: Text(
                        CommonStrings.invalidFormat,
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: theme.colorScheme.error,
                        ),
                      ),
                    ),
                  )
                else if (!addressProblem &&
                    !complaint &&
                    recipientIssues.any(
                      (issue) =>
                          (issue.isFailure || issue.uncertain) &&
                          issue.data['obsolete'] != true &&
                          issue.data['resolution'] != 'cancelled' &&
                          issue.data['resolution'] != 'waiting_repair',
                    ))
                  Padding(
                    padding: const EdgeInsets.only(top: 6),
                    child: Text(
                      t('emailHint'),
                      style: theme.textTheme.bodySmall,
                    ),
                  ),
              ],
            )
          else
            SelectableText(
              _order!['data']['email']?.toString() ?? '',
              style: theme.textTheme.bodyLarge,
            ),
          const SizedBox(height: 16),
          ExpansionTile(
            key: PageStorageKey((
              'email-delivery-details',
              widget.occasionId,
              widget.orderId,
            )),
            tilePadding: EdgeInsets.zero,
            childrenPadding: const EdgeInsets.only(bottom: 8),
            title: Text(t('details'), style: theme.textTheme.bodyMedium),
            children: [
              if (currentIssues.length > 1 && writable) ...[
                Text(t('chooseMessage'), style: secondaryStyle),
                RadioGroup<String>(
                  groupValue: selected?.messageId,
                  onChanged: (value) =>
                      setState(() => _selectedMessage = value),
                  child: Column(
                    children: [
                      for (final issue in currentIssues)
                        RadioListTile<String>(
                          contentPadding: EdgeInsets.zero,
                          title: Text(issue.description),
                          subtitle: Text(
                            issue.data['recipient']?.toString() ??
                                issue.originalRecipient,
                          ),
                          value: issue.messageId,
                          enabled: !_locked,
                        ),
                    ],
                  ),
                ),
              ],
              for (final issue in issues)
                Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: Align(
                    alignment: Alignment.centerLeft,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          issue.description,
                          style: theme.textTheme.bodyMedium?.copyWith(
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        if (issue.reasonDescription != null)
                          Text(issue.reasonDescription!, style: secondaryStyle),
                        if (issue.originalRecipient != _order!['data']['email'])
                          SelectableText(
                            key: PageStorageKey((
                              'email-original-recipient',
                              issue.messageId,
                            )),
                            '${t('original')}: ${issue.originalRecipient}',
                            style: secondaryStyle,
                          ),
                        if (issue.data['obsolete'] == true)
                          Text(t('obsolete'), style: secondaryStyle),
                      ],
                    ),
                  ),
                ),
            ],
          ),
        ],
        if (_contact.pendingContact != null) ...[
          Text(
            '${t('pendingContact')}: ${jsonDecode(_contact.pendingContact!.requestJson)['p_email']}',
          ),
          TextButton(
            onPressed: _locked ? null : _recover,
            child: Text(t('recoverContact')),
          ),
        ],
        if (_feedback != null)
          Padding(
            padding: const EdgeInsets.only(top: 12),
            child: Semantics(liveRegion: true, child: Text(_feedback!)),
          ),
        if (_stale)
          TextButton(
            onPressed: _locked ? null : _contact.load,
            child: Text(t('reload')),
          ),
      ],
    );
    final actions = <Widget>[
      if (writable) ...[
        if (widget.showSaveOnlyAction)
          FilledButton(
            onPressed:
                _locked || _contact.pendingContact != null || !valid || !changed
                ? null
                : () => _save(false, selected),
            child: Text(t('saveOnly')),
          ),
        OutlinedButton(
          onPressed:
              _locked ||
                  _contact.pendingContact != null ||
                  !valid ||
                  uncertain ||
                  recipientBlocked ||
                  addressMustChange ||
                  ambiguous ||
                  sourceBlocked
              ? null
              : () => _save(true, selected),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (_busy) ...[
                SizedBox(
                  key: const ValueKey('order-email-send-progress'),
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    semanticsLabel: EmailDeliveryStrings.state('sending'),
                  ),
                ),
                const SizedBox(width: 8),
              ],
              Flexible(child: Text(sendLabel)),
            ],
          ),
        ),
      ],
    ];
    return widget.hostBuilder?.call(body, actions, _locked) ??
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            body,
            Wrap(spacing: 8, runSpacing: 8, children: actions),
          ],
        );
  }
}

/// Standalone host for authorized callers, sharing the contact session.
class OrderEmailRepairDialog extends StatelessWidget {
  const OrderEmailRepairDialog({
    super.key,
    required this.orderId,
    required this.occasionId,
    this.sourceMessageId,
    this.read,
    this.commands,
    this.canWrite,
    this.onChanged,
    this.onShowOrder,
  });
  final int orderId, occasionId;
  final String? sourceMessageId;
  final Future<dynamic> Function(String, Map<String, dynamic>)? read;
  final OrderCommands? commands;
  final bool? canWrite;
  final Future<void> Function()? onChanged;
  final VoidCallback? onShowOrder;
  @override
  Widget build(BuildContext context) => OrderEmailContactEditor(
    orderId: orderId,
    occasionId: occasionId,
    sourceMessageId: sourceMessageId,
    read: read,
    commands: commands,
    canWrite: canWrite,
    onChanged: onChanged,
    onShowOrder: onShowOrder,
    hostBuilder: (body, actions, busy) => AppAlertDialog(
      dismissible: !busy,
      content: SizedBox(width: 480, child: SingleChildScrollView(child: body)),
      actions: [
        ...actions,
        if (onShowOrder != null)
          PopupMenuButton<String>(
            enabled: !busy,
            onSelected: (_) {
              Navigator.of(context).pop();
              onShowOrder!();
            },
            itemBuilder: (_) => [
              PopupMenuItem(
                value: 'show',
                child: Text(EmailDeliveryStrings.recovery('show')),
              ),
            ],
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Text(EmailDeliveryStrings.recovery('more')),
            ),
          ),
      ],
    ),
  );
}
