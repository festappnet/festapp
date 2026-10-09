import 'package:fstapp/components/users/widgets/google_login_panel.dart';
import 'package:fstapp/services/google_auth_service.dart';
import 'package:auto_route/auto_route.dart';
import 'package:fstapp/router_service.dart';
import 'package:fstapp/components/forms/models/form_field_model.dart';
import 'package:fstapp/components/forms/models/form_model.dart';
import 'package:fstapp/data_services/auth_service.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:fstapp/components/users/user_strings.dart';
import 'package:fstapp/components/forms/models/holder_models/form_holder.dart';
import 'package:fstapp/components/forms/widgets_view/form_helper.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:fstapp/services/toast_helper.dart';
import 'package:fstapp/styles/styles_config.dart';
import 'package:fstapp/theme_config.dart';
import 'package:fstapp/widgets/buttons_helper.dart';
import 'package:fstapp/app_config.dart';
import 'package:url_launcher/link.dart';
import 'package:flutter_form_builder/flutter_form_builder.dart';

@RoutePage()
class SignupPage extends StatefulWidget {
  static const ROUTE = "signup";
  const SignupPage({super.key});

  @override
  _SignupPageState createState() => _SignupPageState();
}

class _SignupPageState extends State<SignupPage> {
  Widget _registrationNotice(BuildContext context) {
    final style = Theme.of(context).textTheme.bodySmall?.copyWith(
        color: Theme.of(context).colorScheme.onSurfaceVariant, height: 1.6);
    final links = {
      '{terms}': (UserStrings.signupTerms, AppConfig.termsUrl),
      '{privacy}': (UserStrings.signupPrivacy, AppConfig.privacyUrl),
    };
    final spans = <InlineSpan>[];
    final notice = UserStrings.signupLegalNotice;
    var cursor = 0;
    for (final match in RegExp(r'\{terms\}|\{privacy\}').allMatches(notice)) {
      spans.add(TextSpan(text: notice.substring(cursor, match.start)));
      final link = links[match.group(0)]!;
      spans.add(WidgetSpan(
        alignment: PlaceholderAlignment.baseline,
        baseline: TextBaseline.alphabetic,
        child: Link(
          uri: Uri.parse(link.$2),
          target: LinkTarget.blank,
          builder: (context, followLink) => InkWell(
            onTap: followLink,
            child: Text(link.$1,
                style: style?.copyWith(
                    color: Theme.of(context).colorScheme.primary,
                    decoration: TextDecoration.underline)),
          ),
        ),
      ));
      cursor = match.end;
    }
    spans.add(TextSpan(text: notice.substring(cursor)));
    return Text.rich(TextSpan(children: spans),
        style: style, textAlign: TextAlign.center);
  }

  bool _isLoading = false;
  bool _isRegistrationSuccess = false;
  Map<String, dynamic>? fieldsData;
  FormHolder? formHolder;

  List<FormFieldModel> entryForm = [
    FormFieldModel(id: 1, type: FormHelper.fieldTypeName, isRequired: true),
    FormFieldModel(id: 2, type: FormHelper.fieldTypeSurname, isRequired: true),
    FormFieldModel(id: 3, type: FormHelper.fieldTypeSex),
    FormFieldModel(id: 4, type: FormHelper.fieldTypeEmail, isRequired: true),
    FormFieldModel(id: 5, type: FormHelper.fieldTypeCity, isRequired: true),
    FormFieldModel(id: 6, type: FormHelper.fieldTypeBirthYear),
  ];

  final _formKey = GlobalKey<FormBuilderState>();

  @override
  void initState() {
    super.initState();
    GoogleAuthService.state.addListener(_googleStateChanged);
  }

  void _googleStateChanged() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    GoogleAuthService.state.removeListener(_googleStateChanged);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    var formModel = FormModel();
    formModel.relatedFields = entryForm;
    formHolder = FormHolder.fromFormFieldModel(formModel);
    formHolder!.controller = FormHolderController(globalKey: _formKey);
    return Scaffold(
      appBar: AppBar(
        centerTitle: true,
        title: Text(UserStrings.signUp),
        leading: BackButton(
          onPressed: () => RouterService.popOrHome(context),
        ),
      ),
      body: Align(
        alignment: Alignment.topCenter,
        child: ConstrainedBox(
          constraints: BoxConstraints(maxWidth: StylesConfig.appMaxWidth),
          child: SingleChildScrollView(
            child: Padding(
              padding: const EdgeInsets.all(12.0),
              child: _isRegistrationSuccess
                  ? Padding(
                      padding: const EdgeInsets.fromLTRB(12, 88, 12, 12),
                      child: RichText(
                          textAlign: TextAlign.center,
                          text: TextSpan(
                            children: [
                              TextSpan(
                                style: TextStyle(
                                    fontSize: 18,
                                    color: ThemeConfig.blackColor(context)),
                                text: UserStrings.credentialsSentLong(
                                    fieldsData?["email"]?.toString() ?? ""),
                              ),
                              const WidgetSpan(
                                child: Padding(
                                    padding: EdgeInsets.fromLTRB(6, 0, 0, 0),
                                    child: Icon(Icons.check_circle)),
                              )
                            ],
                          )))
                  : FormBuilder(
                      key: _formKey,
                      child: AutofillGroup(
                        child: Column(children: [
                          GoogleLoginPanel(
                              onAuthenticated: () =>
                                  RouterService.handlePostLoginNavigation(
                                      context,
                                      useReplacement: true)),
                          if (!GoogleAuthService.isContinuation) ...[
                            ...FormHelper.getAllFormFields(context,
                                formHolder!.controller!.globalKey, formHolder!),
                            const SizedBox(
                              height: 16,
                            ),
                            ButtonsHelper.bigButton(
                              context: context,
                              onPressed: _isLoading
                                  ? null
                                  : () async {
                                      TextInput.finishAutofillContext();
                                      if (_formKey.currentState
                                              ?.saveAndValidate() ??
                                          false) {
                                        setState(() {
                                          _isLoading = true;
                                        });
                                        var data = FormHelper.getDataFromForm(
                                            formHolder!, true);
                                        fieldsData = Map<String, dynamic>.from(
                                            data[FormHelper.metaFields]);
                                        fieldsData![AuthService.metaLang] =
                                            EasyLocalization.of(context)
                                                ?.locale
                                                .toString();
                                        var resp = await AuthService.register(
                                            fieldsData!);
                                        if (resp["code"] == 200) {
                                          ToastHelper.Show(
                                              context,
                                              UserStrings
                                                  .registrationAlmostComplete);
                                          setState(() {
                                            _isRegistrationSuccess = true;
                                          });
                                        } else if (resp["code"] == 409) {
                                          ToastHelper.Show(
                                              context,
                                              UserStrings.emailInUse(
                                                  resp["email"]),
                                              severity: ToastSeverity.NotOk);
                                        } else {
                                          ToastHelper.Show(context,
                                              UserStrings.registrationFailed,
                                              severity: ToastSeverity.NotOk);
                                        }
                                        setState(() {
                                          _isLoading = false;
                                        });
                                      }
                                    },
                              label: UserStrings.signUp,
                              color: ThemeConfig.seed1,
                              textColor: Colors.white,
                              isEnabled: !_isLoading,
                              height: 50.0,
                              width: 250.0,
                            ),
                            const SizedBox(height: 12),
                            _registrationNotice(context),
                          ],
                        ]),
                      ),
                    ),
            ),
          ),
        ),
      ),
    );
  }
}
