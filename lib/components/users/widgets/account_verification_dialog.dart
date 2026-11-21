import 'package:flutter/services.dart';
import 'package:fstapp/components/_shared/common_strings.dart';
import 'package:fstapp/components/users/user_strings.dart';
import 'package:fstapp/data_services/auth_service.dart';
import 'package:fstapp/services/account_mfa_settings_service.dart';
import 'package:fstapp/widgets/app_dialog.dart';
import 'package:material_ui/material_ui.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

Future<bool> signInWithAccountVerification(
  BuildContext context,
  Future<void> Function() signIn,
) async {
  try {
    await signIn();
    return true;
  } on AccountVerificationRequired catch (error) {
    if (!context.mounted) {
      await AuthService.cancelAccountVerification(error.verification);
      return false;
    }
    return showAccountVerification(context, error.verification);
  }
}

Future<bool> showAccountVerification(
  BuildContext context,
  PendingAccountVerification verification,
) async {
  if (verification.recovery) {
    await showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (_) => _AccountRecoveryDialog(verification: verification),
    );
    return false;
  }
  final verified = await showDialog<bool>(
    context: context,
    barrierDismissible: false,
    builder: (dialogContext) => AuthenticatorCodeForm(
      factors: verification.factors,
      securityKeys: verification.securityKeys,
      verify: (factorId, code) =>
          AuthService.verifyAccountLogin(verification, factorId!, code),
      verifySecurityKey: (factorId) =>
          AuthService.verifyAccountWebAuthn(verification, factorId),
      onDismiss: (verified) => Navigator.of(dialogContext).pop(verified),
    ),
  );
  if (verified == true) return true;
  await AuthService.cancelAccountVerification(verification);
  return false;
}

class _AccountRecoveryDialog extends StatefulWidget {
  const _AccountRecoveryDialog({required this.verification});

  final PendingAccountVerification verification;

  @override
  State<_AccountRecoveryDialog> createState() => _AccountRecoveryDialogState();
}

class _AccountRecoveryDialogState extends State<_AccountRecoveryDialog> {
  final _code = TextEditingController();
  AccountMfaSettingsService? _service;
  TotpSetup? _setup;
  List<String> _replacementMethods = [];
  String? _replacementMethod;
  bool _busy = false;
  bool _completed = false;
  bool _failed = false;

  @override
  void initState() {
    super.initState();
    if (widget.verification.canReplaceFactor &&
        AccountMfaSettingsService.supportsChannel) {
      _service = AccountMfaSettingsService.open();
      _load();
    }
  }

  Future<void> _load() async {
    _busy = true;
    try {
      AuthService.requireCurrentVerification(widget.verification);
      final settings = await _service!.load();
      AuthService.requireCurrentVerification(widget.verification);
      if (mounted) {
        _replacementMethods = settings.registrationMethods
            .where((method) => method != 'passkey')
            .toList();
        _replacementMethod = _replacementMethods.firstOrNull;
      }
    } catch (_) {
      if (mounted) _replacementMethod = null;
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  void dispose() {
    _setup = null;
    _code.dispose();
    _service?.dispose();
    super.dispose();
  }

  Future<void> _start() async {
    if (_busy || _code.text.length != 43) return;
    final code = _code.text;
    _code.clear();
    setState(() {
      _busy = true;
      _failed = false;
    });
    try {
      AuthService.requireCurrentVerification(widget.verification);
      if (_replacementMethod == 'webauthn') {
        await _service!.enrollWebAuthn(recoveryCode: code);
        if (mounted) _completed = true;
      } else {
        final setup = await _service!.enrollTotp(recoveryCode: code);
        if (mounted) _setup = setup;
      }
    } catch (_) {
      if (mounted) _failed = true;
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _verify(TotpSetup setup, String code) async {
    setState(() => _busy = true);
    try {
      await _service!.verifyTotp(setup, code);
      if (!mounted) return;
      _setup = null;
      _completed = true;
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final setup = _setup;
    void close() => Navigator.of(context).pop();
    return PopScope(
      canPop: !_busy,
      child: AppAlertDialog(
        title: Text(UserStrings.accountSecurity('recoveryTitle')),
        onClose: close,
        dismissible: !_busy,
        scrollable: true,
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (_busy) const LinearProgressIndicator(),
            if (_completed)
              Text(UserStrings.accountSecurity('recoveryReplaced'))
            else if (setup != null) ...[
              Text(UserStrings.accountSecurity('recoveryScan')),
              AuthenticatorSetupDetails(setup: setup),
              AuthenticatorCodeForm(verify: (_, code) => _verify(setup, code)),
            ] else if (_replacementMethod != null) ...[
              Text(UserStrings.accountSecurity('recoveryEnter')),
              if (_replacementMethods.length > 1) ...[
                Text(UserStrings.accountSecurity('recoveryMethod')),
                DropdownButton<String>(
                  value: _replacementMethod,
                  isExpanded: true,
                  onChanged: _busy
                      ? null
                      : (method) => setState(() => _replacementMethod = method),
                  items: [
                    for (final method in _replacementMethods)
                      DropdownMenuItem(
                        value: method,
                        child: Text(UserStrings.accountSecurity(method)),
                      ),
                  ],
                ),
              ],
              TextField(
                controller: _code,
                enabled: !_busy,
                autocorrect: false,
                enableSuggestions: false,
                autofillHints: const [AutofillHints.oneTimeCode],
                maxLength: 43,
                inputFormatters: [
                  FilteringTextInputFormatter.allow(RegExp(r'[A-Za-z0-9_-]')),
                ],
                decoration: InputDecoration(
                  labelText: UserStrings.accountSecurity('recoveryCode'),
                  errorText: _failed
                      ? UserStrings.accountSecurity('recoveryError')
                      : null,
                ),
                onChanged: (_) => setState(() => _failed = false),
                onSubmitted: (_) => _start(),
              ),
              FilledButton(
                onPressed: _busy || _code.text.length != 43 ? null : _start,
                child: Text(UserStrings.accountSecurity('recoveryStart')),
              ),
            ] else if (!_busy)
              Text(UserStrings.accountSecurity('recoveryHeld')),
          ],
        ),
        actions: [
          TextButton(
            onPressed: _busy ? null : close,
            child: Text(CommonStrings.close),
          ),
        ],
      ),
    );
  }
}

class AuthenticatorSetupDetails extends StatelessWidget {
  const AuthenticatorSetupDetails({super.key, required this.setup});

  final TotpSetup setup;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      Center(
        child: Semantics(
          label: UserStrings.accountSecurity('qr'),
          image: true,
          child: QrImageView(data: setup.uri, size: 200),
        ),
      ),
      Text(UserStrings.accountSecurity('manual')),
      SelectableText(setup.secret),
      const SizedBox(height: 16),
    ],
  );
}

class AuthenticatorCodeForm extends StatefulWidget {
  const AuthenticatorCodeForm({
    super.key,
    this.factors = const [],
    this.securityKeys = const [],
    required this.verify,
    this.verifySecurityKey,
    this.onDismiss,
  });

  final List<Factor> factors;
  final List<Factor> securityKeys;
  final Future<void> Function(String? factorId, String code) verify;
  final Future<void> Function(String factorId)? verifySecurityKey;
  final ValueChanged<bool>? onDismiss;

  @override
  State<AuthenticatorCodeForm> createState() => _AuthenticatorCodeFormState();
}

class _AuthenticatorCodeFormState extends State<AuthenticatorCodeForm> {
  final _code = TextEditingController();
  bool _busy = false;
  bool _invalid = false;
  bool _invalidKey = false;
  String? _factorId;

  @override
  void dispose() {
    _code.dispose();
    super.dispose();
  }

  void _verify() {
    final code = _code.text;
    if (!RegExp(r'^\d{6}$').hasMatch(code)) return;
    _submit(
      () => widget.verify(_factorId ?? widget.factors.firstOrNull?.id, code),
    );
  }

  Future<void> _submit(
    Future<void> Function() verify, {
    bool securityKey = false,
  }) async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _invalid = false;
      _invalidKey = false;
    });
    try {
      await verify();
      if (mounted) widget.onDismiss?.call(true);
    } on AuthException catch (error) {
      if (!mounted) return;
      if (error.message == 'invalid_session' && widget.onDismiss != null) {
        widget.onDismiss!(false);
      } else {
        _showError(securityKey);
      }
    } catch (_) {
      if (mounted) _showError(securityKey);
    } finally {
      if (mounted) {
        _code.clear();
        setState(() => _busy = false);
      }
    }
  }

  void _showError(bool securityKey) => setState(() {
    _invalid = !securityKey;
    _invalidKey = securityKey;
  });

  @override
  Widget build(BuildContext context) {
    final factors = widget.factors;
    final showCode = factors.isNotEmpty || widget.securityKeys.isEmpty;
    final content = Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (showCode) Text(UserStrings.mfaEnterAuthenticatorCode),
        if (factors.length > 1)
          DropdownButton<String>(
            value: _factorId ?? factors.first.id,
            isExpanded: true,
            onChanged: _busy
                ? null
                : (value) => setState(() => _factorId = value),
            items: [
              for (var index = 0; index < factors.length; index++)
                DropdownMenuItem(
                  value: factors[index].id,
                  child: Text(
                    UserStrings.mfaFactorName(
                      factors[index].friendlyName,
                      '${UserStrings.mfaAuthenticator} ${index + 1}',
                    ),
                  ),
                ),
            ],
          ),
        if (showCode)
          TextField(
            controller: _code,
            autofocus: true,
            enabled: !_busy,
            keyboardType: TextInputType.number,
            autofillHints: const [AutofillHints.oneTimeCode],
            inputFormatters: [FilteringTextInputFormatter.digitsOnly],
            maxLength: 6,
            decoration: InputDecoration(
              labelText: UserStrings.googleCode,
              counterText: '',
              errorText: _invalid ? UserStrings.googleError : null,
            ),
            onChanged: (_) => setState(() => _invalid = false),
            onSubmitted: (_) => _verify(),
          ),
        for (final factor in widget.securityKeys)
          OutlinedButton.icon(
            onPressed: _busy || widget.verifySecurityKey == null
                ? null
                : () => _submit(
                    () => widget.verifySecurityKey!(factor.id),
                    securityKey: true,
                  ),
            icon: const Icon(Icons.key),
            label: Text(
              UserStrings.mfaFactorName(
                factor.friendlyName, UserStrings.mfaVerifySecurityKey,
              ),
            ),
          ),
        if (_invalidKey)
          Semantics(liveRegion: true, child: Text(UserStrings.googleError)),
      ],
    );
    final verifyButton = showCode
        ? FilledButton(
            onPressed: _busy || _code.text.length != 6 ? null : _verify,
            child: Text(UserStrings.googleVerifyCode),
          )
        : null;
    final dismiss = widget.onDismiss;
    if (dismiss == null) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          content,
          if (verifyButton != null) ...[
            const SizedBox(height: 16),
            verifyButton,
          ],
        ],
      );
    }

    void close() => dismiss(false);
    return PopScope(
      canPop: !_busy,
      child: AppAlertDialog(
        title: Text(UserStrings.signIn),
        onClose: close,
        dismissible: !_busy,
        scrollable: true,
        content: content,
        actions: [
          TextButton(
            onPressed: _busy ? null : close,
            child: Text(CommonStrings.cancel),
          ),
          ?verifyButton,
        ],
      ),
    );
  }
}
