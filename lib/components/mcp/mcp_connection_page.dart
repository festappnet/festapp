import 'package:auto_route/auto_route.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:fstapp/app_router.gr.dart';
import 'package:fstapp/app_config.dart';
import 'package:fstapp/data_services/auth_service.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:url_launcher/url_launcher.dart';
import 'mcp_connection_service.dart';
import 'mcp_callback_window.dart';
import 'mcp_callback_browser.dart';
import 'mcp_connection_complete.dart';

typedef McpConnectionRequester = Future<Map<String, dynamic>> Function(
    String request, String operation, Map<String, dynamic> access);

@RoutePage()
class McpConnectionPage extends StatefulWidget {
  static const routePath = '/settings/mcp-connect';
  const McpConnectionPage(
      {super.key,
      @QueryParam('request') this.request,
      this.requester,
      this.isLoggedIn,
      this.accountEmail,
      this.openCallbackWindow});
  final String? request;
  final McpConnectionRequester? requester;
  final bool Function()? isLoggedIn;
  final String? accountEmail;
  final McpCallbackWindow? Function()? openCallbackWindow;
  @override
  State<McpConnectionPage> createState() => _McpConnectionPageState();
}

class _McpConnectionPageState extends State<McpConnectionPage> {
  Map<String, dynamic>? _details;
  final _selected = <int>{};
  bool _wholeUnit = false;
  int? _unitId;
  bool _allowCreate = false;
  bool _loading = false;
  bool _busy = false;
  bool _failed = false;
  bool _waitingForClient = false;
  bool _connected = false;
  bool _confirmationUnknown = false;
  String get _email => AppConfig.removeUserPrefix(widget.accountEmail ??
      Supabase.instance.client.auth.currentUser?.email ??
      '');
  String text(String key) => 'McpConnection.$key'.tr();
  bool get _loggedIn => (widget.isLoggedIn ?? AuthService.isLoggedIn)();
  bool get _validRequest =>
      RegExp(r'^[A-Za-z0-9_-]{43}$').hasMatch(widget.request ?? '');
  Future<Map<String, dynamic>> call(String operation) =>
      (widget.requester ?? McpConnectionService.request)(
          widget.request!,
          operation,
          operation == 'approve'
              ? (_wholeUnit
                  ? {
                      'type': 'unit',
                      'unitId': _unitId,
                      'canCreateOccasions': _allowCreate
                    }
                  : {'type': 'occasions', 'occasionIds': _selected.toList()})
              : {});

  @override
  void initState() {
    super.initState();
    if (_validRequest && _loggedIn) _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _failed = false;
    });
    try {
      final details = await call('details');
      if (mounted) setState(() => _details = details);
    } catch (_) {
      if (mounted) setState(() => _failed = true);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _finish(String operation) async {
    final callback =
        operation == 'approve' && _details?['applicationType'] == 'native'
            ? (widget.openCallbackWindow ?? openMcpCallbackWindow)()
            : null;
    var dispatched = false;
    setState(() {
      _busy = true;
      _failed = false;
    });
    try {
      final result = await call(operation);
      final uri = McpConnectionService.resumeUri(result['resumeUrl']);
      if (callback != null) {
        callback.navigate(uri);
        dispatched = true;
        setState(() => _waitingForClient = true);
        await _confirmCompletion(callback);
        return;
      }
      if (!await launchUrl(uri, webOnlyWindowName: '_self')) {
        throw StateError('Navigation failed');
      }
    } catch (_) {
      if (!dispatched) callback?.close();
      if (mounted) {
        setState(() {
          _failed = true;
          _busy = false;
        });
      }
    }
  }

  Future<void> _confirmCompletion(McpCallbackWindow callback) async {
    try {
      for (var attempt = 0; attempt < 60 && mounted; attempt++) {
        final result = await call('status');
        if (!mounted) return;
        if (result['status'] == 'connected') {
          try {
            callback.close();
          } catch (_) {/* The connection is already verified. */}
          setState(() {
            _connected = true;
            _waitingForClient = false;
            _busy = false;
          });
          return;
        }
        if (result['status'] != 'pending') break;
        await Future<void>.delayed(const Duration(seconds: 1));
      }
    } catch (_) {
      // A failed observation does not prove that the client failed to connect.
    }
    if (mounted) {
      setState(() {
        _confirmationUnknown = true;
        _waitingForClient = false;
        _busy = false;
      });
    }
  }

  Future<void> _login() async {
    await context.router.push(LoginRoute(
        redirect: Uri(
            path: McpConnectionPage.routePath,
            queryParameters: {'request': widget.request!}).toString()));
    if (mounted && _loggedIn) _load();
  }

  @override
  Widget build(BuildContext context) {
    final occasions = (_details?['occasions'] as List? ?? []).cast<Map>();
    final units = (_details?['units'] as List? ?? []).cast<Map>();
    final unitCanCreate =
        units.any((u) => u['id'] == _unitId && u['canCreateOccasions'] == true);
    return Scaffold(
      appBar: AppBar(title: Text('${AppConfig.appName} - ${text('title')}')),
      body: Center(
          child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 640),
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: _connected
              ? McpConnectionComplete(
                  client: _details!['client'].toString(), email: _email)
              : Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                      Text(text(_waitingForClient ? 'finishing' : 'heading'),
                          style: Theme.of(context).textTheme.headlineMedium),
                      const SizedBox(height: 16),
                      if (!_validRequest)
                        Text(text('invalid'))
                      else if (!_loggedIn) ...[
                        Text(text('loginHint')),
                        const SizedBox(height: 16),
                        FilledButton(
                            onPressed: _busy ? null : _login,
                            child: Text(text('login'))),
                        TextButton(
                            onPressed: _busy ? null : () => _finish('cancel'),
                            child: Text(text('cancel'))),
                      ] else if (_loading)
                        const Center(child: CircularProgressIndicator())
                      else if (_waitingForClient) ...[
                        const Center(child: CircularProgressIndicator()),
                        const SizedBox(height: 24),
                        Text(text('waitingForClient'),
                            textAlign: TextAlign.center),
                      ] else if (_confirmationUnknown) ...[
                        Text(text('completionUnknown')),
                      ] else ...[
                        if (_details != null) ...[
                          Text(
                              text('client').replaceAll(
                                  '{client}', _details!['client'].toString()),
                              style: Theme.of(context).textTheme.titleLarge),
                          const SizedBox(height: 8),
                          Text(_email),
                          const SizedBox(height: 16),
                          Text(text('scope')),
                          const SizedBox(height: 16),
                          if (units.isNotEmpty) ...[
                            SwitchListTile(
                              contentPadding: EdgeInsets.zero,
                              title: Text(text('wholeOrganizer')),
                              subtitle: Text(text('wholeOrganizerHint')),
                              value: _wholeUnit,
                              onChanged: _busy
                                  ? null
                                  : (value) => setState(() {
                                        _wholeUnit = value;
                                        _allowCreate = false;
                                        _unitId ??= units.first['id'] as int;
                                      }),
                            ),
                            if (_wholeUnit) ...[
                              DropdownButtonFormField<int>(
                                initialValue: _unitId,
                                decoration: InputDecoration(
                                    labelText: text('organizer')),
                                items: units
                                    .map((u) => DropdownMenuItem<int>(
                                        value: u['id'] as int,
                                        child: Text(u['title'].toString())))
                                    .toList(),
                                onChanged: _busy
                                    ? null
                                    : (value) => setState(() {
                                          _unitId = value;
                                          _allowCreate = false;
                                        }),
                              ),
                              if (_details!['canRequestCreate'] == true &&
                                  unitCanCreate)
                                CheckboxListTile(
                                  contentPadding: EdgeInsets.zero,
                                  title: Text(text('allowCreate')),
                                  subtitle: Text(text('allowCreateHint')),
                                  value: _allowCreate,
                                  onChanged: _busy
                                      ? null
                                      : (value) => setState(
                                          () => _allowCreate = value == true),
                                ),
                            ],
                          ],
                          if (!_wholeUnit)
                            Text(text('choose'),
                                style: Theme.of(context).textTheme.titleMedium),
                          if (!_wholeUnit)
                            ...occasions.map((occasion) => CheckboxListTile(
                                  contentPadding: EdgeInsets.zero,
                                  title: Text(occasion['title'].toString()),
                                  value: _selected.contains(occasion['id']),
                                  onChanged: _busy
                                      ? null
                                      : (selected) => setState(() {
                                            if (selected == true) {
                                              _selected
                                                  .add(occasion['id'] as int);
                                            } else {
                                              _selected.remove(occasion['id']);
                                            }
                                          }),
                                )),
                          const SizedBox(height: 16),
                          Text(text('duration')),
                          const SizedBox(height: 16),
                          Wrap(spacing: 12, runSpacing: 12, children: [
                            FilledButton(
                                onPressed: _busy ||
                                        (_wholeUnit
                                            ? _unitId == null
                                            : _selected.isEmpty)
                                    ? null
                                    : () => _finish('approve'),
                                child: Text(_busy
                                    ? text('connecting')
                                    : text('approve'))),
                            OutlinedButton(
                                onPressed:
                                    _busy ? null : () => _finish('cancel'),
                                child: Text(text('cancel'))),
                          ]),
                        ],
                        if (_failed) ...[
                          const SizedBox(height: 16),
                          Text(text('error')),
                          if (!_busy)
                            TextButton(
                                onPressed: _load, child: Text(text('retry'))),
                        ],
                      ],
                    ]),
        ),
      )),
    );
  }
}
