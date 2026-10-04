import 'package:fstapp/components/_shared/common_strings.dart';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:fstapp/services/exception_handler.dart';
import 'email_delivery_strings.dart';

class EmailDeliveryHistory extends StatefulWidget {
  final int? occasionId;
  final int? organizationId;
  final String? userId;
  final bool embedded;
  final int? orderId;
  final Future<dynamic> Function(String, Map<String, dynamic>)? read;
  const EmailDeliveryHistory(
      {super.key,
      this.occasionId,
      this.orderId,
      this.organizationId,
      this.userId,
      this.embedded = false,
      this.read});
  @override
  State<EmailDeliveryHistory> createState() => _EmailDeliveryHistoryState();
}

class _EmailDeliveryHistoryState extends State<EmailDeliveryHistory> {
  final List<Map<String, dynamic>> _messages = [];
  bool _loading = false;
  bool _more = true;
  bool _organizationScope = false;
  String? _state;
  String? _kind;
  DateTime? _since;
  Map<String, dynamic>? _overview;
  Future<dynamic> _read(String name, {required Map<String, dynamic> params}) =>
      widget.read?.call(name, params) ??
      Supabase.instance.client.rpc(name, params: params);
  Future<void> _reload() async {
    _messages.clear();
    _more = true;
    await _load();
  }

  Future<void> _loadOverview() async {
    if (widget.orderId != null || widget.userId != null) return;
    final result = await ExceptionHandler.guard(context,
        futureFunction: () => _read('get_email_delivery_overview', params: {
              'p_occasion': _organizationScope ? null : widget.occasionId,
              'p_organization': widget.organizationId
            }));
    if (mounted && result is Map)
      setState(() => _overview = Map<String, dynamic>.from(result));
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _load();
      _loadOverview();
    });
  }

  Future<void> _load() async {
    if (_loading || !_more) return;
    setState(() => _loading = true);
    final result = await ExceptionHandler.guard(context,
        futureFunction: () => _read('get_email_delivery_page', params: {
              'p_occasion': _organizationScope ? null : widget.occasionId,
              'p_order': widget.orderId,
              'p_limit': 30,
              'p_organization': widget.organizationId,
              'p_user': widget.userId,
              'p_state': _state,
              'p_kind': _kind,
              'p_since': _since?.toUtc().toIso8601String(),
              if (_messages.isNotEmpty) 'p_before': _messages.last['id'],
            }));
    if (!mounted) return;
    setState(() {
      _loading = false;
      if (result is List) {
        _messages
            .addAll(result.map((m) => Map<String, dynamic>.from(m as Map)));
        _more = result.length == 30;
      }
    });
  }

  Future<void> _detail(String messageId) async {
    final result = await ExceptionHandler.guard(context,
        futureFunction: () => _read('get_email_delivery_detail',
            params: {'p_message': messageId}));
    if (!mounted || result is! Map) return;
    await showDialog<void>(
        context: context,
        builder: (_) => AlertDialog(
              title: Text(EmailDeliveryStrings.history),
              content: SizedBox(
                  width: 400,
                  child: SingleChildScrollView(
                      child: Column(
                          mainAxisSize: MainAxisSize.min,
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                        Text(EmailDeliveryStrings.state(
                            result['message']?['tracking_policy'] == 'disabled'
                                ? 'tracking_disabled'
                                : result['message']?['clicked_at'] != null
                                    ? 'click'
                                    : result['message']?['opened_at'] != null
                                        ? 'open'
                                        : 'not_observed')),
                        if (result['message']?['last_error'] ==
                            'post_action_failed')
                          Text(
                              EmailDeliveryStrings.state('post_action_failed')),
                        for (final entry in (result['attempts'] as List? ?? []))
                          Text(
                              '${EmailDeliveryStrings.state(entry['state'].toString())} - ${entry['at']}${entry['error'] == null ? '' : ' - ${entry['error']}'}'),
                        for (final entry in (result['events'] as List? ?? []))
                          Text(
                              '${EmailDeliveryStrings.state(entry['type'].toString())} - ${entry['at']}'),
                      ]))),
            ));
  }

  @override
  Widget build(BuildContext context) {
    final content = SizedBox(
        width: 600,
        height: 480,
        child: Column(children: [
          Padding(
              padding: const EdgeInsets.all(16),
              child: Text(EmailDeliveryStrings.history,
                  style: Theme.of(context).textTheme.titleLarge)),
          if (widget.organizationId != null &&
              widget.occasionId != null &&
              widget.orderId == null &&
              widget.userId == null)
            SwitchListTile(
              title: Text(EmailDeliveryStrings.organizationScope),
              value: _organizationScope,
              onChanged: _loading
                  ? null
                  : (value) {
                      setState(() => _organizationScope = value);
                      _reload();
                      _loadOverview();
                    },
            ),
          Wrap(spacing: 12, children: [
            SizedBox(
                width: 240,
                child: DropdownButton<String>(
                    isExpanded: true,
                    value: _state,
                    hint: Text(EmailDeliveryStrings.title),
                    items: [
                      for (final state in [
                        'pending',
                        'accepted',
                        'delivery',
                        'bounce',
                        'complaint',
                        'unknown',
                        'dead',
                        'retry_wait',
                        'open',
                        'click'
                      ])
                        DropdownMenuItem(
                            value: state,
                            child: Text(EmailDeliveryStrings.state(state),
                                overflow: TextOverflow.ellipsis))
                    ],
                    onChanged: _loading
                        ? null
                        : (value) {
                            _state = value;
                            _reload();
                          })),
            SizedBox(
                width: 240,
                child: DropdownButton<String>(
                    isExpanded: true,
                    value: _kind,
                    hint: Text(EmailDeliveryStrings.history),
                    items: [
                      for (final kind in [
                        'order_confirmation',
                        'order_tickets',
                        'order_reminder',
                        'registration',
                        'sign_in',
                        'reset_password',
                        'gotrue'
                      ])
                        DropdownMenuItem(
                            value: kind,
                            child: Text(EmailDeliveryStrings.kind(kind),
                                overflow: TextOverflow.ellipsis))
                    ],
                    onChanged: _loading
                        ? null
                        : (value) {
                            _kind = value;
                            _reload();
                          })),
            IconButton(
                tooltip: CommonStrings.startDate,
                icon: const Icon(Icons.date_range),
                onPressed: _loading
                    ? null
                    : () async {
                        final date = await showDatePicker(
                            context: context,
                            firstDate: DateTime(2020),
                            lastDate: DateTime.now(),
                            initialDate: _since ?? DateTime.now());
                        if (!mounted || date == null) return;
                        _since = date;
                        _reload();
                      }),
            if (_state != null || _kind != null || _since != null)
              IconButton(
                  icon: const Icon(Icons.filter_alt_off),
                  onPressed: _loading
                      ? null
                      : () {
                          _state = null;
                          _kind = null;
                          _since = null;
                          _reload();
                        }),
          ]),
          if (_overview != null)
            Wrap(spacing: 16, children: [
              for (final key in [
                'accepted',
                'delivered',
                'bounced',
                'complained',
                'feedback_overdue',
                'unknown',
                'dead'
              ])
                Text('${EmailDeliveryStrings.state({
                      'delivered': 'delivery',
                      'bounced': 'bounce',
                      'complained': 'complaint'
                    }[key] ?? key)}: ${_overview![key]}')
            ]),
          Expanded(
              child: ListView(children: [
            for (final m in _messages)
              ListTile(
                title: Text(
                    EmailDeliveryStrings.kind(m['message_kind'].toString())),
                subtitle:
                    Text(EmailDeliveryStrings.state(m['state'].toString())),
                onTap: () => _detail(m['message_id'].toString()),
              )
          ])),
          if (_loading) const LinearProgressIndicator(),
          if (_more && !_loading)
            TextButton(onPressed: _load, child: const Icon(Icons.expand_more)),
        ]));
    return widget.embedded ? content : Dialog(child: content);
  }
}
