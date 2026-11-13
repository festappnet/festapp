import 'package:fstapp/components/users/widgets/account_connections_link.dart';
import 'package:auto_route/auto_route.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:material_ui/material_ui.dart';
import 'package:fstapp/app_router.gr.dart';
import 'package:fstapp/app_config.dart';
import 'package:fstapp/data_services/auth_service.dart';
import 'package:fstapp/services/utilities_all.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';

import 'mcp_connection_service.dart';
import 'mcp_callback_window.dart';
import 'mcp_callback_browser.dart';
import 'mcp_connection_complete.dart';

typedef McpConnectionRequester = Future<Map<String, dynamic>> Function(
  String request,
  String operation,
  Map<String, dynamic> access,
);

@RoutePage()
class McpConnectionPage extends StatefulWidget {
  static const routePath = '/settings/mcp-connect';
  const McpConnectionPage({
    super.key,
    @QueryParam('request') this.request,
    this.requester,
    this.isLoggedIn,
    this.accountEmail,
    this.openCallbackWindow,
  });
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
  bool _loading = false;
  bool _busy = false;
  bool _failed = false;
  bool _waitingForClient = false;
  bool _connected = false;
  bool _confirmationUnknown = false;
  String get _email => AppConfig.removeUserPrefix(
    widget.accountEmail ??
        Supabase.instance.client.auth.currentUser?.email ??
        '',
  );
  String text(String key) => 'McpConnection.$key'.tr();
  bool get _loggedIn => (widget.isLoggedIn ?? AuthService.isLoggedIn)();
  bool get _validRequest =>
      RegExp(r'^[A-Za-z0-9_-]{43}$').hasMatch(widget.request ?? '');
  Map<String, dynamic> get _selection => _wholeUnit
      ? {
          'type': 'unit',
          'unitId': _unitId,
          'canCreateOccasions':
              _details?['canRequestCreate'] == true &&
              (_details?['units'] as List? ?? []).any(
                (unit) =>
                    unit['id'] == _unitId && unit['canCreateOccasions'] == true,
              ),
        }
      : {'type': 'occasions', 'occasionIds': _selected.toList()};

  Future<Map<String, dynamic>> call(
    String operation, {
    Map<String, String>? mfa,
  }) =>
      (widget.requester ??
      (request, operation, access) =>
          McpConnectionService.request(request, operation, access, mfa: mfa))(
        widget.request!,
        operation,
        operation == 'approve'
            ? (_details?.containsKey('requestedPermissions') == true
                  ? {
                      'consentVersion': 2,
                      if (_details?['api'] is Map)
                        'apiReview': {
                          ...Map<String, dynamic>.from(_details!['api'] as Map),
                          'version': 1,
                        },
                      'selection': _selection,
                      'permissions': List<String>.from(
                        _details!['requestedPermissions'] as List,
                      ),
                    }
                  : _selection)
            : {},
      );

  @override
  void initState() {
    super.initState();
    if (_validRequest && _loggedIn) _load();
  }

  Factor? get _totpFactor {
    if (widget.requester != null) return null;
    final factors = Supabase.instance.client.auth.currentUser?.factors ?? [];
    for (final factor in factors) {
      if (factor.status == FactorStatus.verified &&
          factor.factorType == FactorType.totp) {
        return factor;
      }
    }
    return null;
  }

  Future<String?> _mfaCode(String hint) => showDialog<String>(
    context: context,
    builder: (_) => _McpMfaCodeDialog(
      label: text('mfaCode'),
      hint: text(hint),
      cancel: text('cancel'),
      verify: text('mfaVerify'),
    ),
  );

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _failed = false;
    });
    try {
      if (widget.requester == null) {
        final auth = Supabase.instance.client.auth;
        if (auth.currentUser?.factors?.any(
              (f) => f.status == FactorStatus.verified,
            ) ==
            true) {
          final assurance = auth.mfa.getAuthenticatorAssuranceLevel();
          if (assurance.currentLevel != AuthenticatorAssuranceLevels.aal2) {
            final factor = _totpFactor;
            if (factor == null) throw StateError('MFA authenticator required');
            final code = await _mfaCode('mfaLoginHint');
            if (code == null || !mounted) return;
            await auth.mfa.challengeAndVerify(factorId: factor.id, code: code);
          }
        }
      }
      final details = await call('details');
      final requested = details['requestedPermissions'] as List? ?? [];
      final labels = details['requestedPermissionLabels'] as Map? ?? {};
      if (requested.any((scope) => labels[scope] is! String)) {
        throw const FormatException('Missing canonical permission labels');
      }
      if (mounted) setState(() => _details = details);
    } catch (_) {
      if (mounted) setState(() => _failed = true);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _finish(String operation) async {
    Map<String, String>? mfa;
    final factor = operation == 'approve' ? _totpFactor : null;
    if (factor != null) {
      final code = await _mfaCode('mfaApprovalHint');
      if (code == null || !mounted) return;
      mfa = {'factorId': factor.id, 'code': code};
    }
    if (!mounted) return;
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
      final result = await call(operation, mfa: mfa);
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
          } catch (_) {
            /* The connection is already verified. */
          }
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
    await context.router.push(
      LoginRoute(
        redirect: Uri(
          path: McpConnectionPage.routePath,
          queryParameters: {
            'request': widget.request!,
            if (Uri.base.queryParameters['issuer'] case final String issuer)
              'issuer': issuer,
          },
        ).toString(),
      ),
    );
    if (mounted && _loggedIn) _load();
  }

  @override
  Widget build(BuildContext context) {
    final occasions = (_details?['occasions'] as List? ?? []).cast<Map>();
    final units = (_details?['units'] as List? ?? []).cast<Map>();
    final unitTitles = <int, String>{
      for (final unit in units) unit['id'] as int: unit['title'].toString(),
    };
    final occasionsByUnit = <int?, List<Map>>{};
    for (final occasion in occasions) {
      (occasionsByUnit[occasion['unitId'] as int?] ??= []).add(occasion);
    }
    String unitTitle(int? id) =>
        unitTitles[id] ??
        (id == null ? text('organizer') : '${text('organizer')} #$id');
    int byName(String a, String b) =>
        Utilities.removeDiacritics(a.toLowerCase())
            .compareTo(Utilities.removeDiacritics(b.toLowerCase()));
    final groups = occasionsByUnit.entries.toList()
      ..sort((a, b) => byName(unitTitle(a.key), unitTitle(b.key)));
    for (final group in groups) {
      group.value.sort(
        (a, b) => byName(a['title'].toString(), b['title'].toString()),
      );
    }
    return Scaffold(
      appBar: AppBar(title: Text('${AppConfig.appName} - ${text('title')}')),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 640),
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: _connected
                ? McpConnectionComplete(
                    client: _details!['client'].toString(),
                    email: _email,
                  )
                : Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Text(
                        text(_waitingForClient ? 'finishing' : 'heading'),
                        style: Theme.of(context).textTheme.headlineMedium,
                      ),
                      const SizedBox(height: 16),
                      if (!_validRequest)
                        Text(text('invalid'))
                      else if (!_loggedIn) ...[
                        Text(text('loginHint')),
                        const SizedBox(height: 16),
                        FilledButton(
                          onPressed: _busy ? null : _login,
                          child: Text(text('login')),
                        ),
                        TextButton(
                          onPressed: _busy ? null : () => _finish('cancel'),
                          child: Text(text('cancel')),
                        ),
                      ] else if (_loading)
                        const Center(child: CircularProgressIndicator())
                      else if (_waitingForClient) ...[
                        const Center(child: CircularProgressIndicator()),
                        const SizedBox(height: 24),
                        Text(
                          text('waitingForClient'),
                          textAlign: TextAlign.center,
                        ),
                      ] else if (_confirmationUnknown) ...[
                        Text(text('completionUnknown')),
                      ] else ...[
                        if (_details != null) ...[
                          Text(
                            text('client').replaceAll(
                              '{client}',
                              _details!['client'].toString(),
                            ),
                            style: Theme.of(context).textTheme.titleLarge,
                          ),
                          const SizedBox(height: 8),
                          if (_details?['api'] is Map) ...[
                            Text('API: ${_details!['api']['resource']}'),
                            Text('Data: ${_details!['api']['dataProfile']}'),
                          ],
                          Text(_email),
                          const SizedBox(height: 16),
                          Text(text('sameRights')),
                          for (final scope
                              in (_details?['requestedPermissions'] as List? ??
                                  []))
                            Padding(
                              padding: const EdgeInsets.only(top: 8),
                              child: Text(
                                text(
                                  (_details!['requestedPermissionLabels']
                                          as Map)[scope]
                                      as String,
                                ),
                              ),
                            ),
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
                                      _unitId ??= units.first['id'] as int;
                                    }),
                            ),
                            if (_wholeUnit) ...[
                              DropdownButtonFormField<int>(
                                initialValue: _unitId,
                                decoration: InputDecoration(
                                  labelText: text('organizer'),
                                ),
                                items: units
                                    .map(
                                      (u) => DropdownMenuItem<int>(
                                        value: u['id'] as int,
                                        child: Text(u['title'].toString()),
                                      ),
                                    )
                                    .toList(),
                                onChanged: _busy
                                    ? null
                                    : (value) => setState(() {
                                        _unitId = value;
                                      }),
                              ),
                            ],
                          ],
                          if (!_wholeUnit)
                            Text(
                              text('choose'),
                              style: Theme.of(context).textTheme.titleMedium,
                            ),
                          if (!_wholeUnit && occasions.length > 100)
                            Text(text('selectionLimit')),
                          if (!_wholeUnit && occasions.isNotEmpty)
                            CheckboxListTile(
                              key: const ValueKey('mcp-select-all'),
                              contentPadding: EdgeInsets.zero,
                              title: Text(text('selectAll')),
                              tristate: true,
                              value: _selected.isEmpty
                                  ? false
                                  : occasions.every(
                                      (o) => _selected.contains(o['id']),
                                    )
                                  ? true
                                  : null,
                              onChanged: _busy || occasions.length > 100
                                  ? null
                                  : (_) => setState(() {
                                      final all = occasions.every(
                                        (o) => _selected.contains(o['id']),
                                      );
                                      _selected.clear();
                                      if (!all) {
                                        _selected.addAll(
                                          occasions.map((o) => o['id'] as int),
                                        );
                                      }
                                    }),
                            ),
                          if (!_wholeUnit)
                            for (final group in groups) ...[
                              const SizedBox(height: 20),
                              Semantics(
                                header: true,
                                child: Text(
                                  unitTitle(group.key),
                                  key: ValueKey('mcp-unit-${group.key}'),
                                  style: Theme.of(context)
                                      .textTheme
                                      .titleMedium,
                                ),
                              ),
                              ...group.value.map(
                                (occasion) => CheckboxListTile(
                                  contentPadding: EdgeInsets.zero,
                                  title: Text(occasion['title'].toString()),
                                  value: _selected.contains(occasion['id']),
                                  onChanged:
                                      _busy ||
                                          (!_selected.contains(
                                                occasion['id'],
                                              ) &&
                                              _selected.length >= 100)
                                      ? null
                                      : (selected) => setState(() {
                                          if (selected == true) {
                                            _selected.add(
                                              occasion['id'] as int,
                                            );
                                          } else {
                                            _selected.remove(occasion['id']);
                                          }
                                        }),
                                ),
                              ),
                            ],
                          const SizedBox(height: 16),
                          Text(text('duration')),
                          const AccountConnectionsLink(),
                          const SizedBox(height: 16),
                          Wrap(
                            spacing: 12,
                            runSpacing: 12,
                            children: [
                              FilledButton(
                                onPressed:
                                    _busy ||
                                        (_wholeUnit
                                            ? _unitId == null
                                            : _selected.isEmpty ||
                                                  _selected.length > 100)
                                    ? null
                                    : () => _finish('approve'),
                                child: Text(
                                  _busy ? text('connecting') : text('approve'),
                                ),
                              ),
                              OutlinedButton(
                                onPressed: _busy
                                    ? null
                                    : () => _finish('cancel'),
                                child: Text(text('cancel')),
                              ),
                            ],
                          ),
                        ],
                        if (_failed) ...[
                          const SizedBox(height: 16),
                          Text(text('error')),
                          if (!_busy)
                            TextButton(
                              onPressed: _load,
                              child: Text(text('retry')),
                            ),
                        ],
                      ],
                    ],
                  ),
          ),
        ),
      ),
    );
  }
}

class _McpMfaCodeDialog extends StatefulWidget {
  const _McpMfaCodeDialog({
    required this.label,
    required this.hint,
    required this.cancel,
    required this.verify,
  });
  final String label, hint, cancel, verify;
  @override
  State<_McpMfaCodeDialog> createState() => _McpMfaCodeDialogState();
}

class _McpMfaCodeDialogState extends State<_McpMfaCodeDialog> {
  final _controller = TextEditingController();
  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: Text(widget.label),
    content: Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(widget.hint),
        TextField(
          controller: _controller,
          autofocus: true,
          obscureText: true,
          keyboardType: TextInputType.number,
          autofillHints: const [AutofillHints.oneTimeCode],
          inputFormatters: [
            FilteringTextInputFormatter.digitsOnly,
            LengthLimitingTextInputFormatter(6),
          ],
          decoration: InputDecoration(labelText: widget.label),
        ),
      ],
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.of(context).pop(),
        child: Text(widget.cancel),
      ),
      ValueListenableBuilder<TextEditingValue>(
        valueListenable: _controller,
        builder: (_, value, child) => TextButton(
          onPressed: value.text.length == 6
              ? () => Navigator.of(context).pop(_controller.text)
              : null,
          child: Text(widget.verify),
        ),
      ),
    ],
  );
}
