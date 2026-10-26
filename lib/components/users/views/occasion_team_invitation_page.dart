import 'package:auto_route/auto_route.dart';
import 'package:material_ui/material_ui.dart';
import 'package:fstapp/app_config.dart';
import 'package:fstapp/components/occasion/admin_page.dart';
import 'package:fstapp/components/users/occasion_team_invitation_strings.dart';
import 'package:fstapp/components/users/views/login_page.dart';
import 'package:fstapp/components/users/widgets/profile_legal_link.dart';
import 'package:fstapp/data_services/auth_service.dart';
import 'package:fstapp/router_service.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

typedef OccasionTeamInvitationLoader = Future<Map<String, dynamic>> Function(
  String token,
);
typedef OccasionTeamInvitationAcceptor = Future<Map<String, dynamic>> Function(
  String token, {
  String? password,
});

/// A capability link is read on opening. Accepting it always requires an
/// explicit action; existing accounts authenticate through the normal login.
@RoutePage()
class OccasionTeamInvitationPage extends StatefulWidget {
  static const ROUTE = 'team-invitation';
  const OccasionTeamInvitationPage({
    super.key,
    @QueryParam('token') this.token,
    this.loader,
    this.acceptor,
    this.isLoggedIn,
  });

  final String? token;
  final OccasionTeamInvitationLoader? loader;
  final OccasionTeamInvitationAcceptor? acceptor;
  final bool Function()? isLoggedIn;

  @override
  State<OccasionTeamInvitationPage> createState() =>
      _OccasionTeamInvitationPageState();
}

class _OccasionTeamInvitationPageState
    extends State<OccasionTeamInvitationPage> {
  final _form = GlobalKey<FormState>();
  final _password = TextEditingController();
  final _confirmation = TextEditingController();
  Map<String, dynamic>? _invitation;
  bool _loading = true;
  bool _busy = false;
  bool _success = false;
  bool _newAccount = false;
  String? _error;

  String text(String key) => OccasionTeamInvitationStrings.text(key);
  bool get _loggedIn => (widget.isLoggedIn ?? AuthService.isLoggedIn)();

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _password.dispose();
    _confirmation.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    final token = widget.token;
    if (token == null || token.trim().isEmpty) {
      setState(() {
        _loading = false;
        _error = 'invalid';
      });
      return;
    }
    try {
      final result = await (widget.loader?.call(token) ??
          Supabase.instance.client.rpc(
            'get_occasion_team_invitation',
            params: {'p_token': token},
          ).then((value) => Map<String, dynamic>.from(value as Map)));
      if (!mounted) return;
      if (result['organization'] != AppConfig.organization ||
          result['email'] is! String ||
          result['link'] is! String) {
        throw const FormatException('Invalid invitation');
      }
      setState(() {
        _invitation = result;
        _loading = false;
      });
    } catch (_) {
      // Tokens, email addresses and passwords must never enter application logs.
      if (mounted) {
        setState(() {
          _loading = false;
          _error = 'invalid';
        });
      }
    }
  }

  Future<void> _accept() async {
    if (_busy || _invitation == null) return;
    final registering = _invitation!['existingAccount'] != true && !_loggedIn;
    if (registering && !_form.currentState!.validate()) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final password = registering ? _password.text : null;
      final result =
          await (widget.acceptor?.call(widget.token!, password: password) ??
              Supabase.instance.client.rpc(
                'accept_occasion_team_invitation',
                params: {'p_token': widget.token!, 'p_password': password},
              ).then((value) => Map<String, dynamic>.from(value as Map)));
      if (!mounted) return;
      if (result['accepted'] != true) throw StateError('Not accepted');
      _password.clear();
      _confirmation.clear();
      setState(() {
        _success = true;
        _newAccount = result['newAccount'] == true || registering;
      });
    } catch (_) {
      if (mounted) setState(() => _error = 'acceptFailed');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _switchAccount() async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      await AuthService.logout();
      if (mounted) _login();
    } catch (_) {
      if (mounted) setState(() => _error = 'acceptFailed');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  String get _eventPath =>
      '/${Uri.encodeComponent(_invitation!['link'] as String)}/${AdminPage.ROUTE}';

  void _login({bool accepted = false}) {
    final redirect = accepted
        ? _eventPath
        : Uri(
            path: '/${OccasionTeamInvitationPage.ROUTE}',
            queryParameters: {'token': widget.token!},
          ).toString();
    RouterService.navigate(
      context,
      Uri(
        path: '/${LoginPage.ROUTE}',
        queryParameters: {'redirect': redirect},
      ).toString(),
    );
  }

  @override
  Widget build(BuildContext context) {
    final invitation = _invitation;
    final existing = invitation?['existingAccount'] == true;
    final registering = !existing && !_loggedIn;
    return Scaffold(
      appBar: AppBar(title: Text(text('title'))),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 560),
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: _loading
                ? const Center(child: CircularProgressIndicator())
                : Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        _success
                            ? Icons.check_circle_outline
                            : Icons.group_outlined,
                        size: 48,
                        color: Theme.of(context).colorScheme.primary,
                      ),
                      const SizedBox(height: 20),
                      if (invitation != null) ...[
                        Text(
                          invitation['title'] as String? ?? '',
                          style: Theme.of(context).textTheme.headlineSmall,
                          textAlign: TextAlign.center,
                        ),
                        if (invitation['unitTitle'] != null)
                          Text(
                            invitation['unitTitle'].toString(),
                            textAlign: TextAlign.center,
                          ),
                        const SizedBox(height: 24),
                      ],
                      if (_error != null)
                        Semantics(
                          liveRegion: true,
                          child: Padding(
                            padding: const EdgeInsets.only(bottom: 16),
                            child: Text(
                              text(_error!),
                              style: TextStyle(
                                color: Theme.of(context).colorScheme.error,
                              ),
                            ),
                          ),
                        ),
                      if (_success) ...[
                        Text(text(_newAccount ? 'accountCreated' : 'accepted')),
                        const SizedBox(height: 20),
                        FilledButton(
                          onPressed: () => _newAccount
                              ? _login(accepted: true)
                              : RouterService.navigate(context, _eventPath),
                          child: Text(
                            text(_newAccount ? 'login' : 'openEvent'),
                          ),
                        ),
                      ] else if (invitation != null) ...[
                        Text(text('accessDescription')),
                        const SizedBox(height: 12),
                        Text(
                            "${text('roleLabel')}: ${text(invitation['role'] == 'read_only' ? 'roleReadOnly' : 'roleEditor')}",
                            style: Theme.of(context).textTheme.titleMedium),
                        const SizedBox(height: 16),
                        SelectableText(
                          invitation['email'] as String,
                          textAlign: TextAlign.center,
                        ),
                        const SizedBox(height: 16),
                        if (existing && !_loggedIn) ...[
                          Text(text('existingAccount')),
                          const SizedBox(height: 16),
                          FilledButton(
                            onPressed: _login,
                            child: Text(text('login')),
                          ),
                        ] else ...[
                          if (_loggedIn) ...[
                            Text(text('signedInNotice')),
                            TextButton(
                              onPressed: _busy ? null : _switchAccount,
                              child: Text(text('switchAccount')),
                            ),
                          ],
                          if (registering)
                            Form(
                              key: _form,
                              child: Column(
                                children: [
                                  Text(text('newAccountDescription')),
                                  const SizedBox(height: 16),
                                  TextFormField(
                                    key: const ValueKey('invitation-password'),
                                    controller: _password,
                                    enabled: !_busy,
                                    obscureText: true,
                                    autocorrect: false,
                                    enableSuggestions: false,
                                    autofillHints: const [
                                      AutofillHints.newPassword,
                                    ],
                                    decoration: InputDecoration(
                                      labelText: text('password'),
                                    ),
                                    validator: (value) =>
                                        (value?.length ?? 0) < 8
                                            ? text('passwordShort')
                                            : null,
                                  ),
                                  const SizedBox(height: 16),
                                  TextFormField(
                                    key: const ValueKey(
                                      'invitation-confirmation',
                                    ),
                                    controller: _confirmation,
                                    enabled: !_busy,
                                    obscureText: true,
                                    autocorrect: false,
                                    enableSuggestions: false,
                                    decoration: InputDecoration(
                                      labelText: text('confirmation'),
                                    ),
                                    validator: (value) =>
                                        value != _password.text
                                            ? text('passwordMismatch')
                                            : null,
                                  ),
                                  const SizedBox(height: 16),
                                  Text(text('registrationNotice')),
                                  const AppLegalLinks(),
                                ],
                              ),
                            ),
                          const SizedBox(height: 20),
                          FilledButton(
                            onPressed: _busy ? null : _accept,
                            child: Text(
                              text(
                                _busy
                                    ? 'working'
                                    : registering
                                        ? 'createAndAccept'
                                        : 'accept',
                              ),
                            ),
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
