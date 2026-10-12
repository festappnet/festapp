import 'package:fstapp/components/users/widgets/google_login_panel.dart';
import 'package:fstapp/services/google_auth_service.dart';
import 'package:auto_route/auto_route.dart';
import 'package:fstapp/data_services/rights_service.dart';
import 'package:fstapp/components/users/user_strings.dart';
import 'package:fstapp/components/users/login_feedback.dart';
import 'package:fstapp/router_service.dart';
import 'package:fstapp/data_services/auth_service.dart';
import 'package:fstapp/components/users/views/forgot_password_page.dart';
import 'package:fstapp/components/app_management/settings_page.dart';
import 'package:fstapp/components/users/views/signup_page.dart';
import 'package:fstapp/components/users/widgets/profile_legal_link.dart';
import 'package:fstapp/services/toast_helper.dart';
import 'package:fstapp/styles/styles_config.dart';
import 'package:fstapp/theme_config.dart';
import 'package:fstapp/widgets/buttons_helper.dart';
import 'package:fstapp/widgets/internal_form_fields.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:fstapp/app_config.dart';
import 'package:fstapp/widgets/password_field.dart';
import 'package:fstapp/components/features/feature_constants.dart';
import 'package:fstapp/components/features/feature_service.dart';
import 'package:fstapp/components/reception/reception_strings.dart';
import 'package:fstapp/components/reception/login_qr_transition.dart';
import 'package:fstapp/components/reception/login_qr_scanner_page.dart';
import 'package:fstapp/app_router.gr.dart';

@RoutePage()
class LoginPage extends StatefulWidget {
  static const ROUTE = "login";
  final String? redirect;
  const LoginPage({super.key, @QueryParam('redirect') this.redirect});

  @override
  _LoginPageState createState() => _LoginPageState();
}

class _LoginPageState extends State<LoginPage> {
  bool _isLoading = false;
  LoginQrTransitionState? _qrTransition;

  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  final _formKey = GlobalKey<FormState>();

  @override
  void initState() {
    super.initState();
    GoogleAuthService.state.addListener(_googleStateChanged);
    if (AppConfig.isWebclientSupported) {
      AuthService.tryAuthUser().then((isLoggedIn) {
        if (isLoggedIn) {
          _checkAutoRedirect();
        }
      });
    }
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!AppConfig.isAppSupported) {
        _checkAutoRedirect();
      }
    });
  }

  void _googleStateChanged() {
    if (mounted) setState(() {});
  }

  Future<void> _checkAutoRedirect() async {
    if (GoogleAuthService.hasCallback || GoogleAuthService.isContinuation) {
      return;
    }
    final loggedIn = await ensureAuthenticatedSession(
      isLoggedIn: AuthService.isLoggedIn,
      restoreSession: AuthService.tryAuthUser,
    );
    if (!mounted ||
        !loggedIn ||
        GoogleAuthService.hasCallback ||
        GoogleAuthService.isContinuation) {
      return;
    }
    await _refreshSignedInStatus(null);
  }

  Future<void> _recoverAuthenticatedNavigation() async {
    if (!mounted) return;
    RouterService.popOrHome(context);
  }

  @override
  void dispose() {
    GoogleAuthService.state.removeListener(_googleStateChanged);
    _emailController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    List<Widget> actions = [
      if (FeatureService.isFeatureEnabled(FeatureConstants.reception))
        IconButton(
          tooltip: ReceptionStrings.scan,
          icon: const Icon(Icons.qr_code_scanner),
          onPressed: _isLoading ? null : _loginWithQr,
        ),
      IconButton(
        icon: Icon(Icons.settings),
        onPressed: () => RouterService.navigate(context, SettingsPage.ROUTE),
      ),
    ];

    return Scaffold(
      appBar: AppBar(
        centerTitle: true,
        title: Text(UserStrings.signIn),
        leading: BackButton(
          onPressed: () => RouterService.popOrHome(context),
        ),
        actions: actions,
      ),
      bottomNavigationBar: const SafeArea(
        top: false,
        child: Padding(
          padding: EdgeInsets.fromLTRB(16, 8, 16, 12),
          child: AppLegalLinks(),
        ),
      ),
      body: Stack(children: [
        Align(
          alignment: Alignment.topCenter,
          child: ConstrainedBox(
            constraints: BoxConstraints(maxWidth: StylesConfig.formMaxWidth),
            child: SingleChildScrollView(
              child: Form(
                key: _formKey,
                child: AutofillGroup(
                  child: Column(
                    children: <Widget>[
                      const SizedBox(
                        height: 24,
                      ),
                      GoogleLoginPanel(
                          returnPath: widget.redirect,
                          onAuthenticated: () =>
                              RouterService.handlePostLoginNavigation(context,
                                  fallbackPath: widget.redirect ??
                                      GoogleAuthService.state.value
                                          .result['returnPath'] as String?,
                                  useReplacement: true)),
                      if (!GoogleAuthService.isContinuation) ...[
                        if (RightsService.occasionLinkModel?.organization
                                ?.isRegistrationEnabled ??
                            false)
                          Container(
                            padding: const EdgeInsets.all(12.0),
                            child: Row(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  Text(UserStrings.firstTime,
                                      style: TextStyle(fontSize: 18)),
                                  const SizedBox(
                                    width: 16,
                                  ),
                                  TextButton(
                                      onPressed: () => RouterService.navigate(
                                          context, SignupPage.ROUTE),
                                      child: Text(UserStrings.signUp,
                                          style: StylesConfig.normalTextStyle))
                                ]),
                          ),
                        Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 15),
                          child: InternalFormFields.email(_emailController),
                        ),
                        Padding(
                          padding: const EdgeInsets.only(
                              left: 15.0, right: 15.0, top: 15, bottom: 0),
                          child: PasswordField(
                              label: UserStrings.passwordOrCode,
                              controller: _passwordController,
                              passwordType: AutofillHints.password),
                        ),
                        const SizedBox(
                          height: 16,
                        ),
                        ButtonsHelper.bigButton(
                          context: context,
                          label: UserStrings.signIn,
                          onPressed: () async {
                            if (_formKey.currentState!.validate()) {
                              TextInput.finishAutofillContext();
                              setState(() {
                                _isLoading = true;
                              });
                              try {
                                await AuthService.login(
                                  AppConfig.getUserPrefix(
                                      _emailController.text),
                                  _passwordController.text,
                                );
                                await finishSuccessfulSignIn(
                                  navigate: () => _refreshSignedInStatus(null),
                                  recoverNavigation:
                                      _recoverAuthenticatedNavigation,
                                  showFeedback: _showSignInSuccess,
                                );
                              } catch (error) {
                                _onError(error);
                              }
                              if (!mounted) return;
                              setState(() {
                                _isLoading = false;
                              });
                            }
                          },
                          color: ThemeConfig.seed1,
                          textColor: Colors.white,
                          isEnabled: !_isLoading,
                        ),
                        const SizedBox(
                          height: 8,
                        ),
                        Container(
                            padding: const EdgeInsets.all(8.0),
                            alignment: Alignment.topRight,
                            child: TextButton(
                                onPressed: () => RouterService.navigate(
                                    context, ForgotPasswordPage.ROUTE),
                                child: Text(UserStrings.forgotPassword,
                                    style: StylesConfig.normalTextStyle))),
                      ],
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
        if (_qrTransition != null)
          Positioned.fill(
            child: LoginQrTransition(
              state: _qrTransition!,
              title: _qrTransition == LoginQrTransitionState.success
                  ? ReceptionStrings.signedIn
                  : ReceptionStrings.signingIn,
              subtitle: _qrTransition == LoginQrTransitionState.success
                  ? ReceptionStrings.openingApp
                  : ReceptionStrings.verifyingQr,
            ),
          ),
      ]),
    );
  }

  Future<void> _loginWithQr() async {
    final credential = await context.router
        .push<ReceptionLoginCredential>(const LoginQrScannerRoute());
    if (credential == null || !mounted) return;
    await _loginWithReceptionCredential(
      () => switch (credential.type) {
        ReceptionLoginCredentialType.qr =>
          AuthService.loginWithQr(credential.value),
        ReceptionLoginCredentialType.manualCode =>
          AuthService.loginWithManualCode(credential.value),
      },
    );
  }

  Future<void> _loginWithReceptionCredential(
      Future<void> Function() authenticate) async {
    setState(() {
      _isLoading = true;
      _qrTransition = LoginQrTransitionState.signingIn;
    });
    try {
      await authenticate();
      if (!mounted) return;
      setState(() => _qrTransition = LoginQrTransitionState.success);
      await Future<void>.delayed(const Duration(milliseconds: 900));
      if (!mounted) return;
      await finishSuccessfulSignIn(
        navigate: () => _refreshSignedInStatus(null),
        recoverNavigation: _recoverAuthenticatedNavigation,
        showFeedback: _showSignInSuccess,
      );
    } catch (error) {
      if (mounted) setState(() => _qrTransition = null);
      _onError(error);
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
          _qrTransition = null;
        });
      }
    }
  }

  Future<void> _refreshSignedInStatus(dynamic value) async {
    final loggedIn = await ensureAuthenticatedSession(
      isLoggedIn: AuthService.isLoggedIn,
      restoreSession: AuthService.tryAuthUser,
    );
    if (!mounted) return;
    if (loggedIn) {
      await RouterService.handlePostLoginNavigation(context,
          fallbackPath: widget.redirect ??
              GoogleAuthService.state.value.result['returnPath'] as String?);
    }
  }

  Future<void> _showSignInSuccess() async {
    final visibleContext = RouterService.router.navigatorKey.currentContext;
    if (visibleContext == null) return;
    await ToastHelper.Show(visibleContext, UserStrings.signInSuccess);
  }

  void _onError(Object error) {
    ToastHelper.Show(context, UserStrings.invalidCredentials,
        severity: ToastSeverity.NotOk);
  }
}
