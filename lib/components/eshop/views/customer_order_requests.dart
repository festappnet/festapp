import 'package:material_ui/material_ui.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:uuid/uuid.dart';

import '../../forms/customer_order_changes.dart';

/// Working support evidence. All financial transitions stay in server owners.
class CustomerOrderRequests extends StatefulWidget {
  const CustomerOrderRequests({
    super.key,
    required this.requests,
    required this.canWrite,
    required this.onChanged,
  });
  final List<Map<String, dynamic>> requests;
  final bool canWrite;
  final Future<void> Function() onChanged;
  @override
  State<CustomerOrderRequests> createState() => _CustomerOrderRequestsState();
}

class _CustomerOrderRequestsState extends State<CustomerOrderRequests> {
  String? _selected, _action, _message, _command;
  final _response = TextEditingController();
  bool _busy = false;
  @override
  void dispose() {
    _response.dispose();
    super.dispose();
  }

  Future<void> _perform(Map<String, dynamic> request) async {
    if (_busy) return;
    if (_action == 'resolve' && _response.text.trim().isEmpty) {
      setState(() => _message = 'responseRequired');
      return;
    }
    _command ??= const Uuid().v4();
    setState(() => _busy = true);
    try {
      await Supabase.instance.client
          .rpc(
            'command_customer_order_request',
            params: {
              'p_request': request['id'],
              'p_action': _action,
              'p_command': _command,
              'p_expected_at': request['updatedAt'],
              'p_response': _response.text.trim(),
            },
          )
          .timeout(const Duration(seconds: 20));
      if (mounted) {
        setState(() {
          _selected = null;
          _action = null;
          _command = null;
          _message = 'success';
        });
      }
      await widget.onChanged();
    } catch (_) {
      if (mounted) setState(() => _message = 'staffConflict');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (widget.requests.isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            customerChangeText('requests'),
            style: Theme.of(context).textTheme.titleLarge,
          ),
          Text(customerChangeText('staffHelp')),
          if (_message != null)
            Semantics(
              liveRegion: true,
              child: Text(customerChangeText(_message!)),
            ),
          if (_busy) const LinearProgressIndicator(),
          for (final request in widget.requests) ...[
            const Divider(),
            Text(
              '${customerChangeText(request['operation'])}: ${customerChangeText(request['status'])}',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            if (request['reason'] != null)
              SelectableText(
                '${customerChangeText('reason')}: ${request['reason']}',
              ),
            if (request['response'] != null)
              SelectableText(
                '${customerChangeText('response')}: ${request['response']}',
              ),
            if (widget.canWrite &&
                const ['open', 'approved'].contains(request['status'])) ...[
              if (_selected != request['id'])
                Wrap(
                  spacing: 12,
                  children: [
                    for (final action
                        in request['status'] == 'open'
                            ? ['approve', 'reject', 'resolve']
                            : ['resolve'])
                      OutlinedButton(
                        onPressed: _busy
                            ? null
                            : () {
                                setState(() {
                                  _selected = request['id'];
                                  _action = action;
                                  _command = null;
                                  _response.clear();
                                  _message = null;
                                });
                              },
                        child: Text(customerChangeText(action)),
                      ),
                  ],
                )
              else ...[
                Text(customerChangeText(_action!)),
                TextFormField(
                  controller: _response,
                  enabled: !_busy,
                  maxLength: 2000,
                  minLines: 2,
                  maxLines: 4,
                  decoration: InputDecoration(
                    labelText: customerChangeText('response'),
                  ),
                  onChanged: (_) {
                    _command = null;
                  },
                ),
                Wrap(
                  spacing: 12,
                  children: [
                    FilledButton(
                      onPressed: _busy ? null : () => _perform(request),
                      child: Text(customerChangeText(_action!)),
                    ),
                    TextButton(
                      onPressed: _busy
                          ? null
                          : () => setState(() => _selected = null),
                      child: Text(customerChangeText('close')),
                    ),
                  ],
                ),
              ],
            ],
          ],
        ],
      ),
    );
  }
}
