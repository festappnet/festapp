import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:fstapp/router_service.dart';
import 'package:fstapp/components/users/views/forgot_password_page.dart';
import 'package:fstapp/app_config.dart';
import 'package:fstapp/components/users/user_strings.dart';
import 'package:fstapp/services/google_auth_service.dart';
import 'package:fstapp/services/launch_url_service.dart';

class GoogleLoginPanel extends StatefulWidget {
  final Future<void> Function() onAuthenticated;
  final Future<bool> Function()? capability;
  final String? returnPath;
  const GoogleLoginPanel(
      {super.key,
      required this.onAuthenticated,
      this.capability,
      this.returnPath});
  @override
  State<GoogleLoginPanel> createState() => _GoogleLoginPanelState();
}

class _GoogleLoginPanelState extends State<GoogleLoginPanel> {
  bool _enabled = false;
  bool _consent = false;
  bool _showPassword = false;
  final _email = TextEditingController(),
      _password = TextEditingController(),
      _name = TextEditingController(),
      _surname = TextEditingController(),
      _code = TextEditingController();
  bool _suggested = false;
  String? _suggestedEmail;
  @override
  void initState() {
    super.initState();
    _suggestProfile(GoogleAuthService.state.value);
    GoogleAuthService.state.addListener(_changed);
    (widget.capability ?? GoogleAuthService.capability)().then((value) {
      if (mounted) setState(() => _enabled = value);
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      GoogleAuthService.finishPending();
    });
  }

  void _changed() {
    if (!mounted) return;
    final state = GoogleAuthService.state.value;
    if (GoogleAuthService.hasCallback) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        GoogleAuthService.finishPending();
      });
    }
    _suggestProfile(state);
    if (state.status == GoogleLoginStatus.authenticated &&
        !GoogleAuthService.navigationClaimed &&
        ModalRoute.of(context)?.isCurrent != false) {
      GoogleAuthService.navigationClaimed = true;
      _navigateAuthenticated();
    }
    setState(() {});
  }

  Future<void> _navigateAuthenticated() async {
    try {
      await widget.onAuthenticated();
      GoogleAuthService.resetCompletedNavigation();
    } catch (_) {
      GoogleAuthService.navigationClaimed = false;
      if (mounted) setState(() => _navigationFailed = true);
    }
  }

  bool _navigationFailed = false;

  void _suggestProfile(GoogleLoginState state) {
    final email = state.result['email'];
    if (email is String && email.isNotEmpty && email != _suggestedEmail) {
      if (_email.text.isEmpty || _email.text == _suggestedEmail) {
        _email.text = email;
      }
      _suggestedEmail = email;
    }
    if (!_suggested && state.result['name'] is String) {
      final names = (state.result['name'] as String).split(' ');
      _name.text = names.first;
      _surname.text = names.skip(1).join(' ');
      _suggested = true;
    }
  }

  @override
  void dispose() {
    GoogleAuthService.state.removeListener(_changed);
    for (final c in [_email, _password, _name, _surname, _code]) {
      c.dispose();
    }
    super.dispose();
  }

  Widget _field(TextEditingController controller, String label,
          {bool password = false, TextInputType? keyboard}) =>
      Padding(
          padding: const EdgeInsets.only(bottom: 16),
          child: TextField(
              controller: controller,
              obscureText: password && !_showPassword,
              keyboardType: keyboard,
              autofillHints: password ? [AutofillHints.password] : null,
              decoration: InputDecoration(
                  labelText: label,
                  suffixIcon: password
                      ? IconButton(
                          tooltip: UserStrings.googlePasswordVisibility,
                          onPressed: () =>
                              setState(() => _showPassword = !_showPassword),
                          icon: Icon(_showPassword
                              ? Icons.visibility_off
                              : Icons.visibility))
                      : null,
                  border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(6)))));
  String _error(String? code) => switch (code) {
        'provider_cancelled' => UserStrings.googleCancelled,
        'attempt_expired' => UserStrings.googleExpired,
        'account_proof_failed' => UserStrings.googleProofError,
        'mfa_required' => UserStrings.googleMfa,
        _ => UserStrings.googleError
      };
  @override
  Widget build(BuildContext context) {
    final state = GoogleAuthService.state.value;
    if (!_enabled && state.status == GoogleLoginStatus.idle) {
      return const SizedBox.shrink();
    }
    final busy = state.status == GoogleLoginStatus.openingGoogle ||
        state.status == GoogleLoginStatus.completing ||
        state.status == GoogleLoginStatus.authenticated;
    final profile = state.status == GoogleLoginStatus.needsProfile ||
        (state.status == GoogleLoginStatus.retryableError &&
            state.result['status'] == 'needs_profile');
    final proof = state.status == GoogleLoginStatus.needsAccountProof ||
        (state.status == GoogleLoginStatus.retryableError &&
            state.result['status'] == 'needs_account_proof');
    final dark = Theme.of(context).brightness == Brightness.dark;
    return Theme(
        data: Theme.of(context).copyWith(
            filledButtonTheme: const FilledButtonThemeData(
                style: ButtonStyle(
                    minimumSize: WidgetStatePropertyAll(Size(64, 44)))),
            textButtonTheme: const TextButtonThemeData(
                style: ButtonStyle(
                    minimumSize: WidgetStatePropertyAll(Size(48, 44))))),
        child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  if (state.error != null)
                    Semantics(
                        liveRegion: true,
                        child: Padding(
                            padding: const EdgeInsets.only(bottom: 16),
                            child: Text(_error(state.error),
                                textAlign: TextAlign.center))),
                  if (_navigationFailed)
                    TextButton(
                        onPressed: () {
                          setState(() => _navigationFailed = false);
                          GoogleAuthService.navigationClaimed = true;
                          _navigateAuthenticated();
                        },
                        child: Text(UserStrings.googleRetry))
                  else if (busy)
                    Padding(
                        padding: const EdgeInsets.all(16),
                        child: Semantics(
                            liveRegion: true,
                            child: Row(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  const SizedBox(
                                      width: 20,
                                      height: 20,
                                      child: CircularProgressIndicator(
                                          strokeWidth: 2)),
                                  const SizedBox(width: 12),
                                  Flexible(
                                      child: Text(state.status ==
                                              GoogleLoginStatus.openingGoogle
                                          ? UserStrings.googleOpening
                                          : UserStrings.googleCompleting))
                                ])))
                  else if (state.status == GoogleLoginStatus.needsMfa ||
                      (state.status == GoogleLoginStatus.retryableError &&
                          state.result['status'] == 'needs_mfa')) ...[
                    Text(UserStrings.googleMfa, textAlign: TextAlign.center),
                    const SizedBox(height: 16),
                    _field(_code, UserStrings.googleCode,
                        keyboard: TextInputType.number),
                    FilledButton(
                        onPressed: () => GoogleAuthService.advance(
                            'mfa_verify', {'mfaCode': _code.text}),
                        child: Text(UserStrings.googleVerifyCode)),
                  ] else if (proof) ...[
                    Text(
                        state.result['intent'] == 'unlink'
                            ? UserStrings.googleUnlinkProof
                            : UserStrings.googleProof,
                        textAlign: TextAlign.center),
                    const SizedBox(height: 20),
                    _field(_email, UserStrings.emailLabel,
                        keyboard: TextInputType.emailAddress),
                    _field(_password, UserStrings.password, password: true),
                    TextButton(
                        onPressed: () => RouterService.navigate(
                            context, ForgotPasswordPage.ROUTE),
                        child: Text(UserStrings.forgotPassword)),
                    FilledButton(
                        onPressed: () => GoogleAuthService.advance(
                                'prove_existing', {
                              'email': _email.text.trim(),
                              'password': _password.text
                            }),
                        child: Text(state.result['intent'] == 'unlink'
                            ? UserStrings.googleUnlink
                            : UserStrings.googleLink)),
                  ] else if (profile) ...[
                    Text(UserStrings.googleProfile,
                        style: Theme.of(context).textTheme.titleLarge,
                        textAlign: TextAlign.center),
                    const SizedBox(height: 20),
                    _field(_name, UserStrings.name),
                    _field(_surname, UserStrings.surname),
                    Text(state.result['email']?.toString() ?? '',
                        textAlign: TextAlign.center),
                    if (state.result['mailboxRequired'] == true) ...[
                      const SizedBox(height: 16),
                      Text(UserStrings.googleMailbox),
                      TextButton(
                          onPressed: () =>
                              GoogleAuthService.advance('mailbox_send', {}),
                          child: Text(UserStrings.googleSendCode)),
                      _field(_code, UserStrings.googleCode,
                          keyboard: TextInputType.number),
                      TextButton(
                          onPressed: () => GoogleAuthService.advance(
                              'mailbox_verify', {'mailboxCode': _code.text}),
                          child: Text(UserStrings.googleVerifyCode)),
                    ],
                    CheckboxListTile(
                        contentPadding: EdgeInsets.zero,
                        controlAffinity: ListTileControlAffinity.leading,
                        value: _consent,
                        onChanged: (v) => setState(() => _consent = v == true),
                        title: Text(UserStrings.googleConsent)),
                    Wrap(alignment: WrapAlignment.center, children: [
                      TextButton(
                          onPressed: () => LaunchUrlService.openExternalUrl(
                              AppConfig.termsUrl),
                          child: Text(UserStrings.googleTerms)),
                      TextButton(
                          onPressed: () => LaunchUrlService.openExternalUrl(
                              AppConfig.privacyUrl),
                          child: Text(UserStrings.googlePrivacy))
                    ]),
                    FilledButton(
                        onPressed:
                            !_consent || state.result['mailboxRequired'] == true
                                ? null
                                : () => GoogleAuthService.advance('register', {
                                      'profile': {
                                        'name': _name.text.trim(),
                                        'surname': _surname.text.trim()
                                      },
                                      'consent': _consent
                                    }),
                        child: Text(UserStrings.googleCreate)),
                    TextButton(
                        onPressed: () => GoogleAuthService.showAccountProof(),
                        child: Text(UserStrings.googleLink)),
                  ] else ...[
                    Text(UserStrings.googleSubtitle,
                        textAlign: TextAlign.center),
                    const SizedBox(height: 16),
                    OutlinedButton(
                        onPressed: () => GoogleAuthService.start(
                            returnPath: widget.returnPath),
                        style: OutlinedButton.styleFrom(
                            minimumSize: const Size(double.infinity, 44),
                            backgroundColor:
                                dark ? const Color(0xff131314) : Colors.white,
                            foregroundColor: dark
                                ? const Color(0xffe3e3e3)
                                : const Color(0xff1f1f1f),
                            shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(6)),
                            side: BorderSide(
                                color: dark
                                    ? const Color(0xff8e918f)
                                    : const Color(0xff747775))),
                        child: Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              SvgPicture.asset('assets/icons/google_g.svg',
                                  width: 20, height: 20),
                              const SizedBox(width: 12),
                              Flexible(child: Text(UserStrings.googleContinue))
                            ])),
                    const SizedBox(height: 20),
                    Row(children: [
                      const Expanded(child: Divider()),
                      Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 12),
                          child: Text(UserStrings.googleOr)),
                      const Expanded(child: Divider())
                    ]),
                  ],
                  if (proof || profile)
                    TextButton(
                        onPressed: () => GoogleAuthService.start(
                            returnPath: widget.returnPath),
                        child: Text(UserStrings.googleRetry)),
                ])));
  }
}
