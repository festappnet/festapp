import 'package:auto_route/auto_route.dart';
import 'package:fstapp/components/users/user_strings.dart';
import 'package:fstapp/components/users/password_change_flow.dart';
import 'package:fstapp/components/users/views/login_page.dart';
import 'package:fstapp/router_service.dart';
import 'package:fstapp/app_config.dart';
import 'package:fstapp/data_services/auth_service.dart';
import 'package:fstapp/services/toast_helper.dart';
import 'package:fstapp/services/dialog_helper.dart';
import 'package:fstapp/styles/styles_config.dart';
import 'package:material_ui/material_ui.dart';
import 'package:flutter/services.dart';
import 'package:fstapp/theme_config.dart';
import 'package:fstapp/widgets/buttons_helper.dart';
import 'package:fstapp/widgets/password_field.dart';

@RoutePage()
class ResetPasswordPage extends StatefulWidget {
  static const ROUTE = "resetPassword";
  final String? token;

  const ResetPasswordPage({@QueryParam('token') this.token, super.key});

  @override
  _ResetPasswordPageState createState() => _ResetPasswordPageState();
}

class _ResetPasswordPageState extends State<ResetPasswordPage> {
  final _formKey = GlobalKey<FormState>();
  final _passwordController = TextEditingController();
  bool _isChangingPassword = false;

  @override
  void dispose() {
    _passwordController.dispose();
    super.dispose();
  }

  Future<void> _changePassword() async {
    if (_isChangingPassword || !_formKey.currentState!.validate()) return;

    TextInput.finishAutofillContext();
    setState(() => _isChangingPassword = true);
    final password = _passwordController.text;
    final result = await completePasswordChange(
      token: widget.token,
      password: password,
      change: AuthService.changePassword,
      signIn: (email, newPassword) => AuthService.login(
        AppConfig.getUserPrefix(email),
        newPassword,
      ),
    );
    if (!mounted) return;
    setState(() => _isChangingPassword = false);

    switch (result) {
      case PasswordChangeResult.changedAndSignedIn:
        RouterService.goBackOrInitial(context);
        final visibleContext = RouterService.router.navigatorKey.currentContext;
        if (visibleContext != null) {
          await ToastHelper.Show(visibleContext, UserStrings.passwordChanged);
        }
        break;
      case PasswordChangeResult.changedSignInRequired:
        await DialogHelper.showInformationDialog(
          context,
          UserStrings.changePasswordTitle,
          UserStrings.passwordChangedSignInRequired,
        );
        if (!mounted) return;
        await RouterService.navigate(context, LoginPage.ROUTE);
        break;
      case PasswordChangeResult.invalidToken:
        await ToastHelper.Show(
          context,
          UserStrings.tokenInvalid,
          severity: ToastSeverity.NotOk,
        );
        break;
      case PasswordChangeResult.failed:
        await ToastHelper.Show(
          context,
          UserStrings.passwordChangeFailedGeneric,
          severity: ToastSeverity.NotOk,
        );
        if (!mounted) return;
        await DialogHelper.showInformationDialog(
          context,
          UserStrings.changePasswordTitle,
          UserStrings.passwordChangeFailedGeneric,
        );
        break;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        centerTitle: true,
        title: Text(UserStrings.newPassword),
        leading: BackButton(
          onPressed: () => RouterService.goBackOrInitial(context),
        ),
      ),
      body: Align(
        alignment: Alignment.center,
        child: ConstrainedBox(
          constraints: BoxConstraints(maxWidth: StylesConfig.appMaxWidth),
          child: SingleChildScrollView(
              child: Form(
            key: _formKey,
            child: AutofillGroup(
              child: Column(
                children: <Widget>[
                  Text(
                    UserStrings.welcomeIn(name: AppConfig.appName),
                    style: const TextStyle(
                        fontSize: 20, fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(
                    height: 16,
                  ),
                  Text(
                    UserStrings.createAPassword,
                    style: const TextStyle(fontSize: 18),
                  ),
                  const SizedBox(
                    height: 64,
                  ),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 15),
                    child: PasswordField(
                        label: UserStrings.newPassword,
                        controller: _passwordController,
                        passwordType: AutofillHints.newPassword),
                  ),
                  const SizedBox(
                    height: 16,
                  ),
                  ButtonsHelper.bigButton(
                    context: context,
                    onPressed: _isChangingPassword ? null : _changePassword,
                    label: UserStrings.changePassword,
                    color: ThemeConfig.seed1,
                    textColor: Colors.white,
                    isEnabled: !_isChangingPassword,
                  ),
                ],
              ),
            ),
          )),
        ),
      ),
    );
  }
}
