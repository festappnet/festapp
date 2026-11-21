import 'package:fstapp/components/_shared/common_strings.dart';
import 'package:fstapp/components/users/user_strings.dart';
import 'package:fstapp/services/account_mfa_settings_service.dart';
import 'package:fstapp/widgets/app_dialog.dart';
import 'package:material_ui/material_ui.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'account_verification_dialog.dart';

Future<bool> showAccountMfaSettings(BuildContext context) async =>
    await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (_) => const _AccountMfaSettings(),
    ) ==
    true;

class _AccountMfaSettings extends StatefulWidget {
  const _AccountMfaSettings();

  @override
  State<_AccountMfaSettings> createState() => _AccountMfaSettingsState();
}

class _AccountMfaSettingsState extends State<_AccountMfaSettings> {
  late final _service = AccountMfaSettingsService.open();
  final _password = TextEditingController();
  List<Factor> _factors = [];
  TotpSetup? _setup;
  Factor? _pendingRemoval;
  Set<String> _registrationMethods = {};
  bool _busy = false;
  bool _proofRequired = false;
  String? _notice;
  String? _error;

  @override
  void initState() {
    super.initState();
    _run(_load);
  }

  @override
  void dispose() {
    _setup = null;
    _password.dispose();
    _service.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    final settings = await _service.load();
    if (!mounted) return;
    _registrationMethods = settings.registrationMethods;
    _factors = settings.factors;
  }

  Future<void> _run(Future<void> Function() action) async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _error = null;
      _notice = null;
    });
    try {
      await action();
    } on AuthException catch (error) {
      if (!mounted) return;
      if (error.message == 'proof_required') {
        _proofRequired = true;
      } else {
        if (error.message == 'invalid_session' ||
            error.message == 'registration_unavailable') {
          _setup = null;
        }
        if (error.message == 'confirm_disable_mfa') {
          _pendingRemoval = null;
          await _load().catchError((Object _) {});
        }
        _error = UserStrings.accountSecurity('error');
      }
    } catch (_) {
      if (mounted) _error = UserStrings.accountSecurity('error');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _confirmCode(Future<void> Function() callback) async {
    if (_busy) throw const AuthException('mfa_operation_failed');
    setState(() => _busy = true);
    try {
      await callback();
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _verifyIdentity(Future<void> Function() verify) async {
    await verify();
    if (!mounted) return;
    setState(() {
      _proofRequired = false;
      _notice = UserStrings.accountSecurity('verified');
    });
  }

  Widget _proof() {
    final totp = _factors
        .where((factor) => factor.factorType == FactorType.totp)
        .toList();
    final securityKeys = AccountMfaSettingsService.supportsWebAuthnVerification
        ? _factors
              .where((factor) => factor.factorType == FactorType.webauthn)
              .toList()
        : const <Factor>[];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(UserStrings.accountSecurity('freshProof')),
        if (totp.isNotEmpty || securityKeys.isNotEmpty)
          AuthenticatorCodeForm(
            factors: totp,
            securityKeys: securityKeys,
            verify: (factorId, code) => _confirmCode(
              () => _verifyIdentity(
                () => _service.reauthenticateWithTotp(factorId!, code),
              ),
            ),
            verifySecurityKey: (factorId) => _confirmCode(
              () => _verifyIdentity(
                () => _service.reauthenticateWithWebAuthn(
                  securityKeys.singleWhere((factor) => factor.id == factorId),
                ),
              ),
            ),
          )
        else if (_factors.isEmpty) ...[
          TextField(
            controller: _password,
            obscureText: true,
            enabled: !_busy,
            autofillHints: const [AutofillHints.password],
            decoration: InputDecoration(labelText: UserStrings.password),
          ),
          FilledButton(
            onPressed: _busy
                ? null
                : () {
                    final password = _password.text;
                    _password.clear();
                    if (password.isEmpty) return;
                    _run(
                      () => _verifyIdentity(
                        () => _service.reauthenticateWithPassword(password),
                      ),
                    );
                  },
            child: Text(UserStrings.signIn),
          ),
        ] else
          Text(UserStrings.accountSecurity('error')),
        TextButton(
          onPressed: _busy
              ? null
              : () => setState(() => _proofRequired = false),
          child: Text(CommonStrings.cancel),
        ),
      ],
    );
  }

  Widget _enrollment(TotpSetup setup) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      AuthenticatorSetupDetails(setup: setup),
      AuthenticatorCodeForm(
        verify: (_, code) => _confirmCode(() async {
          await _service.verifyTotp(setup, code);
          if (!mounted) return;
          _setup = null;
          await _load();
          if (mounted) _notice = UserStrings.accountSecurity('added');
        }),
      ),
      TextButton(
        onPressed: _busy ? null : () => setState(() => _setup = null),
        child: Text(CommonStrings.cancel),
      ),
    ],
  );

  Widget _factor(Factor factor) {
    final last = _factors.length == 1;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          UserStrings.mfaFactorName(
            factor.friendlyName,
            UserStrings.accountSecurity(factor.factorType.name),
          ),
        ),
        if (_pendingRemoval?.id == factor.id) ...[
          Text(
            UserStrings.accountSecurity(
              last ? 'disableConfirm' : 'removeConfirm',
            ),
          ),
          Wrap(
            spacing: 8,
            children: [
              FilledButton(
                onPressed: _busy
                    ? null
                    : () => _run(() async {
                        final signedOut = await _service.remove(
                          factor,
                          confirmDisable: last,
                        );
                        if (!mounted) return;
                        if (signedOut) {
                          Navigator.of(context).pop(true);
                          return;
                        }
                        _pendingRemoval = null;
                        await _load();
                        if (mounted) {
                          _notice = UserStrings.accountSecurity('removed');
                        }
                      }),
                child: Text(
                  UserStrings.accountSecurity(last ? 'disable' : 'remove'),
                ),
              ),
              TextButton(
                onPressed: _busy
                    ? null
                    : () => setState(() => _pendingRemoval = null),
                child: Text(CommonStrings.cancel),
              ),
            ],
          ),
        ] else
          TextButton(
            onPressed: _busy
                ? null
                : () => setState(() => _pendingRemoval = factor),
            child: Text(UserStrings.accountSecurity('remove')),
          ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final setup = _setup;
    return PopScope(
      canPop: !_busy,
      child: AppAlertDialog(
        title: Text(UserStrings.accountSecurity('title')),
        onClose: () => Navigator.of(context).pop(false),
        dismissible: !_busy,
        scrollable: true,
        content: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (_busy) const LinearProgressIndicator(),
            if (_error != null)
              Semantics(liveRegion: true, child: Text(_error!)),
            if (_notice != null)
              Semantics(liveRegion: true, child: Text(_notice!)),
            if (_proofRequired)
              _proof()
            else if (setup != null)
              _enrollment(setup)
            else ...[
              for (final factor in _factors) _factor(factor),
              if (_registrationMethods.contains('totp'))
                FilledButton(
                  onPressed: _busy
                      ? null
                      : () => _run(() async {
                          final setup = await _service.enrollTotp();
                          if (mounted) _setup = setup;
                        }),
                  child: Text(UserStrings.accountSecurity('addTotp')),
                ),
              for (final method in const ['webauthn', 'passkey'])
                if (_registrationMethods.contains(method))
                  OutlinedButton(
                    onPressed: _busy
                        ? null
                        : () => _run(() async {
                            if (method == 'webauthn') {
                              await _service.enrollWebAuthn();
                            } else {
                              await _service.enrollPasskey();
                            }
                            if (!mounted) return;
                            await _load();
                            if (mounted) {
                              _notice = UserStrings.accountSecurity('added');
                            }
                          }),
                    child: Text(
                      UserStrings.accountSecurity(
                        method == 'webauthn' ? 'addKey' : 'addPasskey',
                      ),
                    ),
                  ),
            ],
          ],
        ),
      ),
    );
  }
}
