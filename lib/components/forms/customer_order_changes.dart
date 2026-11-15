import 'package:url_launcher/url_launcher.dart';
import 'package:fstapp/app_config.dart';
import 'package:material_ui/material_ui.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:festapp_core/forms.dart';

import 'customer_order_changes_client.dart';

import 'package:uuid/uuid.dart';

import 'customer_change_location_stub.dart'
    if (dart.library.js_interop) 'customer_change_location_web.dart';

Widget customerChangesHelp(BuildContext context) => TextButton(
  onPressed: () => launchUrl(
    Uri.parse(
      '${AppConfig.webLink}${context.locale.languageCode == 'cs' ? '/napoveda/zakaznicka-samoobsluha/' : '/help/customer-self-service/'}',
    ),
  ),
  child: Text(customerChangeText('help')),
);

String customerChangeText(String key) => 'CustomerSelfService.$key'.tr();

class CustomerOrderChanges extends StatefulWidget {
  const CustomerOrderChanges({
    super.key,
    required this.scope,
    required this.data,
    required this.onChanged,
    this.client,
  });
  final CustomerOrderScope scope;
  final CustomerOrderOverview data;
  final Future<void> Function() onChanged;
  final CustomerOrderChangesApi? client;
  @override
  State<CustomerOrderChanges> createState() => _CustomerOrderChangesState();
}

class _CustomerOrderChangesState extends State<CustomerOrderChanges> {
  late final CustomerOrderChangesApi _client =
      widget.client ?? CustomerOrderChangesClient();
  final _form = GlobalKey<FormState>();
  final _reason = TextEditingController();
  final Map<String, TextEditingController> _fields = {};
  final Map<String, String> _originals = {};
  String? _token, _operation, _message;
  int? _target;
  final Set<int> _selectedTickets = {};
  bool _busy = false;
  int _generation = 0;
  String _command = const Uuid().v4();
  Map<String, dynamic>? _proposal, _preview;
  List<CustomerOrderChangeAction> get _actions =>
      widget.data.allowedActions.where((a) => a.enabled).toList();
  @override
  void initState() {
    super.initState();
    _token = widget.scope.changeToken ?? consumeCustomerChangeToken();
    if (_token != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _loadPreview());
    }
  }

  @override
  void didUpdateWidget(covariant CustomerOrderChanges oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.scope.orderId == widget.scope.orderId &&
        oldWidget.scope.token == widget.scope.token) {
      return;
    }
    _generation++;
    _token = widget.scope.changeToken ?? consumeCustomerChangeToken();
    _proposal = null;
    _preview = null;
    _message = null;
    _operation = null;
    _target = null;
    _busy = false;
    _command = const Uuid().v4();
    _reason.clear();
    for (final controller in _fields.values) {
      controller.dispose();
    }
    _fields.clear();
    _originals.clear();
    if (_token != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _loadPreview());
    }
  }

  @override
  void dispose() {
    _generation++;
    _reason.dispose();
    for (final c in _fields.values) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _run(Future<void> Function() action) async {
    if (_busy) return;
    final generation = _generation;
    setState(() => _busy = true);
    try {
      await action();
    } catch (e) {
      if (mounted && generation == _generation) {
        setState(
          () => _message = e is CustomerOrderChangeException ? e.key : 'failed',
        );
      }
    } finally {
      if (mounted && generation == _generation) setState(() => _busy = false);
    }
  }

  Future<void> _loadPreview() => _run(() async {
    final token = _token;
    final generation = _generation;
    final orderId = widget.scope.orderId;
    if (token == null) return;
    final proposal =
        _proposal ??
        await _client.call({
          'action': 'resolve',
          'token': token,
          'commandId': _command,
        });
    if (proposal['orderId'] != orderId) {
      throw const CustomerOrderChangeException('unavailable');
    }
    final preview = await _client.call({
      'action': 'preview',
      'token': token,
      'operation': proposal['operation'],
      'payload': proposal['payload'],
      'commandId': _command,
    });
    if (mounted && generation == _generation) {
      setState(() {
        _proposal = proposal;
        _preview = preview;
        _message = null;
      });
    }
  });
  Future<void> _confirm() => _run(() async {
    final generation = _generation;
    try {
      await _client.call({
        'action': 'command',
        'token': _token,
        'operation': _proposal!['operation'],
        'payload': _proposal!['payload'],
        'commandId': _command,
        'fingerprint': _preview!['fingerprint'],
      });
      if (mounted && generation == _generation) {
        setState(() {
          _token = null;
          _preview = null;
          _proposal = null;
          _message = 'success';
        });
      }
      if (mounted && generation == _generation) await widget.onChanged();
    } on CustomerOrderChangeException catch (e) {
      if (e.key == 'conflict' && mounted && generation == _generation) {
        setState(() {
          _preview = null;
          _command = const Uuid().v4();
        });
      }
      rethrow;
    }
  });
  void _open(CustomerOrderChangeAction action) {
    for (final c in _fields.values) {
      c.dispose();
    }
    _fields.clear();
    _originals.clear();
    _reason.clear();
    _selectedTickets..clear()..addAll((action.data['tickets'] as List? ?? const []).map((t) => (t['id'] as num).toInt()));
    for (final field in action.data['fields'] as List? ?? const []) {
      final values = field['ticket'] == true
          ? field['values'] as List? ?? const []
          : [
              {'value': field['value']},
            ];
      for (final value in values) {
        final key = '${value['ticketId'] ?? 'order'}:${field['id']}';
        final initial = value['value']?.toString() ?? '';
        _fields[key] = TextEditingController(text: initial);
        _originals[key] = initial;
      }
    }
    setState(() {
      _operation = action.operation;
      _target = null;
      _message = null;
    });
  }

  Future<void> _challenge(String operation, Map<String, dynamic> payload) =>
      _run(() async {
        final generation = _generation;
        await _client.call({
          'action': 'challenge',
          'token': widget.scope.token,
          'orderId': widget.scope.orderId,
          'operation': operation,
          'payload': payload,
        });
        if (mounted && generation == _generation) {
          setState(() {
            _operation = null;
            _message = 'linkSent';
          });
        }
      });
  Widget _edit(CustomerOrderChangeAction action) {
    final children = <Widget>[
      Text(
        customerChangeText(action.operation),
        style: Theme.of(context).textTheme.titleMedium,
      ),
    ];
    for (final field in action.data['fields'] as List? ?? const []) {
      final values = field['ticket'] == true
          ? field['values'] as List? ?? const []
          : [
              {'value': field['value']},
            ];
      for (final value in values) {
        final key = '${value['ticketId'] ?? 'order'}:${field['id']}';
        final person = widget.data.people
            .where((p) => p['id'] == value['ticketId'])
            .firstOrNull;
        final label =
            '${field['title']}${person == null ? '' : ' (${person['label'] ?? value['ticketId']})'}';
        if (field['type'] == 'select_one') {
          children.add(
            DropdownButtonFormField<String>(
              initialValue: _fields[key]!.text.isEmpty
                  ? null
                  : _fields[key]!.text,
              isExpanded: true,
              decoration: InputDecoration(labelText: label),
              items: [
                for (final option in field['options'] as List? ?? const [])
                  DropdownMenuItem(
                    value: option['value'].toString(),
                    child: Text(
                      '${option['title'] ?? option['label'] ?? option['value']}',
                    ),
                  ),
              ],
              onChanged: _busy ? null : (v) => _fields[key]!.text = v ?? '',
              validator: (v) => field['required'] == true && (v ?? '').isEmpty
                  ? customerChangeText('noChanges')
                  : null,
            ),
          );
        } else {
          children.add(
            TextFormField(
              controller: _fields[key],
              enabled: !_busy,
              maxLength: 4000,
              decoration: InputDecoration(labelText: label),
              keyboardType: field['type'] == 'phone'
                  ? TextInputType.phone
                  : TextInputType.text,
              validator: (v) =>
                  field['required'] == true && (v ?? '').trim().isEmpty
                  ? customerChangeText('noChanges')
                  : null,
            ),
          );
        }
      }
    }
    if (action.operation == 'cancel' && (action.data['tickets'] as List? ?? const []).isNotEmpty) {
      children.add(Text(customerChangeText('selectTickets')));
      for (final ticket in action.data['tickets'] as List) {
        final id = (ticket['id'] as num).toInt();
        children.add(CheckboxListTile(contentPadding: EdgeInsets.zero, title: Text(_ticketLabel(id)), value: _selectedTickets.contains(id), onChanged: _busy ? null : (value) => setState(() { if (value == true) { _selectedTickets.add(id); } else { _selectedTickets.remove(id); } })));
      }
    }
    if (action.operation == 'move') {
      children.add(
        DropdownButtonFormField<int>(
          isExpanded: true,
          decoration: InputDecoration(labelText: customerChangeText('target')),
          items: [
            for (final t in action.data['targets'] as List? ?? const [])
              DropdownMenuItem(
                value: t['formId'] as int,
                child: Text(
                  '${_targetLabel(t)}${t['automatic'] == true ? '' : ' (${customerChangeText('manual')})'}',
                ),
              ),
          ],
          onChanged: _busy ? null : (v) => setState(() => _target = v),
          validator: (v) => v == null ? customerChangeText('target') : null,
        ),
      );
    }
    if (action.operation != 'edit') {
      children.add(
        TextFormField(
          controller: _reason,
          enabled: !_busy,
          maxLength: 2000,
          minLines: 2,
          maxLines: 4,
          decoration: InputDecoration(
            labelText: customerChangeText(
              action.data['reasonRequired'] == true
                  ? 'reasonRequired'
                  : 'reason',
            ),
          ),
          validator: (v) =>
              action.data['reasonRequired'] == true && (v ?? '').trim().isEmpty
              ? customerChangeText('reasonRequired')
              : null,
        ),
      );
    }
    children.add(
      Wrap(
        spacing: 12,
        children: [
          FilledButton(
            onPressed: _busy
                ? null
                : () {
                    if (!_form.currentState!.validate()) return;
                    final payload = <String, dynamic>{};
                    if (action.operation == 'edit') {
                      final order = <String, dynamic>{},
                          tickets = <String, dynamic>{};
                      for (final entry in _fields.entries) {
                        if (entry.value.text == _originals[entry.key]) continue;
                        final parts = entry.key.split(':');
                        if (parts[0] == 'order') {
                          order[parts[1]] = entry.value.text;
                        } else {
                          (tickets[parts[0]] ??=
                                  <String, dynamic>{})[parts[1]] =
                              entry.value.text;
                        }
                      }
                      if (order.isEmpty && tickets.isEmpty) {
                        setState(() => _message = 'noChanges');
                        return;
                      }
                      payload.addAll({'order': order, 'tickets': tickets});
                    } else {
                      payload['reason'] = _reason.text.trim();
                      if (action.operation == 'cancel' && (action.data['tickets'] as List? ?? const []).isNotEmpty) {
                        if (_selectedTickets.isEmpty) { setState(() => _message = 'selectOneTicket'); return; }
                        payload['ticketIds'] = _selectedTickets.toList()..sort();
                      }
                      if (_target != null) payload['targetFormId'] = _target;
                    }
                    _challenge(action.operation, payload);
                  },
            child: Text(customerChangeText('sendLink')),
          ),
          TextButton(
            onPressed: _busy ? null : () => setState(() => _operation = null),
            child: Text(customerChangeText('close')),
          ),
        ],
      ),
    );
    return Form(
      key: _form,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: children,
      ),
    );
  }

  String _targetLabel(Map target) => [
    target['title']?.toString(),
    _date(target['startsAt']),
  ].whereType<String>().where((value) => value.isNotEmpty).join(' - ');

  String? _date(dynamic value) {
    final parsed = DateTime.tryParse(value?.toString() ?? '');
    return parsed == null
        ? null
        : DateFormat.yMd(context.locale.toLanguageTag())
              .add_jm()
              .format(parsed.toLocal());
  }

  @override
  Widget build(BuildContext context) {
    final requests = widget.data.changeRequests;
    if (_actions.isEmpty && requests.isEmpty && _token == null) {
      return const SizedBox.shrink();
    }
    final preview = _preview;
    final effect = preview?['effect'] as String?;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            customerChangeText('title'),
            style: Theme.of(context).textTheme.titleLarge,
          ),
          customerChangesHelp(context),
          if (_message != null)
            Semantics(
              liveRegion: true,
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 8),
                child: Text(customerChangeText(_message!)),
              ),
            ),
          if (_busy) const LinearProgressIndicator(),
          if (_token != null) ...[
            if (preview != null) ...[
              Text(
                customerChangeText('preview'),
                style: Theme.of(context).textTheme.titleMedium,
              ),
              Text(customerChangeText('review')),
              Text(
                customerChangeText(
                  preview['partial'] == true ? '${effect}_selected' : const ['edit', 'move', 'cancel', 'withdraw'].contains(effect)
                      ? '${effect}_effect'
                      : effect!,
                ),
              ),
              if (_proposal?['operation'] == 'cancel' && preview['partial'] == true) ...[
                Text(customerChangeText('remainingTickets')),
                for (final id in preview['ticketIds'] as List? ?? const []) Text(_ticketLabel(id)),
              ],
              if (_proposal?['operation'] == 'edit') ...[
                for (final entry
                    in (_proposal!['payload']['order'] as Map? ?? {}).entries)
                  Text('${_fieldLabel(entry.key)}: ${entry.value}'),
                for (final ticket
                    in (_proposal!['payload']['tickets'] as Map? ?? {})
                        .entries) ...[
                  Text('${ticket.key}'),
                  for (final entry in (ticket.value as Map).entries)
                    Text('${_fieldLabel(entry.key)}: ${entry.value}'),
                ],
              ],
              if ((preview['refundAmount'] as num? ?? 0) > 0)
                Text(
                  '${customerChangeText('amount')}: ${preview['refundAmount']} ${preview['currency']}',
                ),
              if (preview['target'] != null) ...[
                Text(
                  '${customerChangeText('target')}: ${_targetLabel(preview['target'])}',
                ),
                Text(customerChangeText('difference')),
                for (final ticket
                    in preview['target']['tickets'] as List? ?? const [])
                  for (final item in ticket['products'] as List? ?? const [])
                    Text(
                      '${item['title']}: ${item['price']} ${item['currency_code']}',
                    ),
              ],
              if ((_proposal?['payload']?['reason'] ?? '')
                  .toString()
                  .isNotEmpty)
                Text(
                  '${customerChangeText('reason')}: ${_proposal!['payload']['reason']}',
                ),
              FilledButton(
                onPressed: _busy ? null : _confirm,
                child: Text(
                  customerChangeText(
                    effect!.startsWith('request_')
                        ? 'confirmRequest'
                        : effect.startsWith('cancel')
                        ? 'confirmCancel'
                        : 'confirm',
                  ),
                ),
              ),
            ] else
              TextButton(
                onPressed: _busy ? null : _loadPreview,
                child: Text(customerChangeText('refreshPreview')),
              ),
            TextButton(
              onPressed: _busy
                  ? null
                  : () => setState(() {
                      _token = null;
                      _preview = null;
                    }),
              child: Text(customerChangeText('close')),
            ),
          ] else ...[
            Text(customerChangeText(_actions.isEmpty ? 'noActions' : 'intro')),
            Wrap(
              spacing: 12,
              children: [
                for (final action in _actions)
                  OutlinedButton(
                    onPressed: _busy ? null : () => _open(action),
                    child: Text(customerChangeText(action.operation)),
                  ),
              ],
            ),
            for (final action in _actions)
              if (action.operation == _operation) _edit(action),
          ],
          if (requests.isNotEmpty) ...[
            Text(
              customerChangeText('requests'),
              style: Theme.of(context).textTheme.titleMedium,
            ),
            for (final request in requests) ...[
              ListTile(
                contentPadding: EdgeInsets.zero,
                title: Text(
                  '${customerChangeText(request['operation'])}: ${customerChangeText(request['status'])}',
                ),
                subtitle: Text(
                  [
                    request['reason'],
                    request['response'],
                  ].whereType<String>().join('\n'),
                ),
              ),
              if (request['canWithdraw'] == true)
                TextButton(
                  onPressed: _busy
                      ? null
                      : () => _challenge('withdraw', {
                          'requestId': request['id'],
                        }),
                  child: Text(customerChangeText('withdraw')),
                ),
            ],
          ],
        ],
      ),
    );
  }

  String _ticketLabel(dynamic id) {
    final person = widget.data.people.where((p) => p['id'].toString() == id.toString()).firstOrNull;
    final items = widget.data.orders.expand((o) => o['items'] as List? ?? const []).where((i) => i['ticketId'].toString() == id.toString());
    return [person?['label'] ?? '${customerChangeText('ticket')} $id', ...items.map((i) => [i['title'],i['spotGroupTitle'],i['spotTitle']].whereType<String>().where((v) => v.isNotEmpty).join(' / '))].join(' - ');
  }

  String _fieldLabel(dynamic id) {
    for (final action in _actions) {
      for (final field in action.data['fields'] as List? ?? const []) {
        if (field['id'].toString() == id.toString()) {
          return field['title'] ?? id.toString();
        }
      }
    }
    return id.toString();
  }
}
