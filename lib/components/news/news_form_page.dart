import 'package:auto_route/auto_route.dart';
import 'package:flutter/foundation.dart';
import 'package:fstapp/services/exception_handler.dart';
import 'package:http/http.dart' as http;
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_form_builder/flutter_form_builder.dart';
import 'package:fstapp/data_services/rights_service.dart';
import 'package:fstapp/components/html/html_strings.dart';
import 'package:fstapp/app_config.dart';
import 'package:fstapp/components/users/user_info_model.dart';
import 'package:fstapp/data_services/auth_service.dart';
import 'package:fstapp/components/html/html_helper.dart';
import 'package:fstapp/styles/styles_config.dart';
import 'package:fstapp/components/html/rich_html_editor.dart';
import 'package:fstapp/components/html/rich_html_editor_controller.dart';
import 'package:fstapp/components/_shared/common_strings.dart';
import 'package:fstapp/components/news/news_strings.dart';
import 'db_news.dart';
import 'news_submission.dart';
export 'news_submission.dart' show NewsSubmission;
import 'package:fstapp/components/news/news_send_confirmation_dialog.dart';
import 'package:fstapp/components/news/news_notification_audience_selector.dart';

@RoutePage()
class NewsFormPage extends StatefulWidget {
  static const ROUTE = "newsForm";
  final Widget? editorOverride;
  final Future<void> Function(NewsSubmission)? onSubmit;

  const NewsFormPage({
    super.key,
    @visibleForTesting this.editorOverride,
    this.onSubmit,
  });

  @override
  _NewsFormPageState createState() => _NewsFormPageState();
}

class _NewsFormPageState extends State<NewsFormPage> {
  final _formKey = GlobalKey<FormBuilderState>();
  late RichHtmlEditorController _controller;
  bool _saving = false;
  bool _confirming = false;
  bool _publishOutcomeUnknown = false;
  NewsNotificationAudience? _audience;
  final FocusNode _toFocusNode = FocusNode();
  UserInfoModel? _currentUser;

  @override
  void initState() {
    super.initState();
    _controller = RichHtmlEditorController(
        owner: HtmlMediaOwner.occasion(RightsService.currentOccasionId()));
  }

  @override
  void didChangeDependencies() async {
    super.didChangeDependencies();
    _currentUser = RightsService.currentUser();
    setState(() {});
  }

  @override
  void dispose() {
    _controller.dispose();
    _toFocusNode.dispose();
    super.dispose();
  }

  Future<void> _stornoPressed() async {
    if (_saving) return;
    if (_controller.isDirty) {
      final discard = await showDialog<bool>(
          context: context,
          builder: (context) =>
              AlertDialog(title: Text(HtmlStrings.discardDraft), actions: [
                TextButton(
                    onPressed: () => Navigator.pop(context, false),
                    child: Text(CommonStrings.storno)),
                TextButton(
                    onPressed: () => Navigator.pop(context, true),
                    child: Text(CommonStrings.ok)),
              ]));
      if (discard != true || !mounted) return;
    }
    Navigator.pop(context);
  }

  Future<void> _sendPressed() async {
    if (_saving || _confirming || _publishOutcomeUnknown || _audience == null)
      return;
    final htmlContent = _controller.html;
    final audience = _audience!;
    final plainText = HtmlHelper.htmlToSnippet(htmlContent).trim();
    if (_controller.isEmpty ||
        (audience.sendsNotification && plainText.isEmpty)) {
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(NewsStrings.contentRequired)));
      return;
    }
    final heading = _formKey.currentState?.fields['heading']?.value as String?;
    final headingDefault = _currentUser?.name ?? '';
    final sendsToSelf = audience.sendsToSelfOnly ||
        (audience.sendsNotification &&
            AppConfig.isPublicNotificationSendingDisabled);
    if (audience.sendsNotification) {
      setState(() => _confirming = true);
      final confirmed = await showDialog<bool>(
          context: context,
          builder: (_) => NewsSendConfirmationDialog(
              isSelfOnly: sendsToSelf,
              isTest: !audience.publishesNews,
              recipientIdentity: _currentUserIdentity,
              heading: heading?.trim().isNotEmpty == true
                  ? heading!.trim()
                  : headingDefault,
              htmlContent: htmlContent));
      if (!mounted) return;
      setState(() => _confirming = false);
      if (confirmed != true) return;
    }
    final delivery = audience.deliveryFields(
        currentUserId: sendsToSelf ? AuthService.currentUserId() : '',
        forceSelfOnly: AppConfig.isPublicNotificationSendingDisabled);
    setState(() => _saving = true);
    final success =
        await ExceptionHandler.guardVoid(context, futureFunction: () async {
      // A notification-only self test has no persistent HTML owner.
      final prepared = audience.publishesNews
          ? await _controller.prepareForSave(context: context)
          : htmlContent;
      try {
        final submission = NewsSubmission(
            content: prepared,
            heading: heading,
            headingDefault: headingDefault,
            addToNews: audience.publishesNews,
            withNotification: audience.sendsNotification,
            recipients: (delivery['to'] as List?)?.cast<String>());
        if (widget.onSubmit != null)
          await widget.onSubmit!(submission);
        else
          await DbNews.publishSubmission(context, submission);
      } on TimeoutException {
        _publishOutcomeUnknown = true;
        rethrow;
      } on http.ClientException {
        _publishOutcomeUnknown = true;
        rethrow;
      }
    });
    if (!mounted) return;
    setState(() => _saving = false);
    if (success) Navigator.pop(context, true);
  }

  String get _currentUserIdentity {
    final name = _currentUser?.toFullNameString() ?? '';
    final email = _currentUser?.email ?? '';
    if (name.isNotEmpty && email.isNotEmpty) return '$name · $email';
    if (name.isNotEmpty) return name;
    return email;
  }

  String get _publishButtonText => switch (_audience) {
        NewsNotificationAudience.none => NewsStrings.publishWithoutNotification,
        NewsNotificationAudience.selfTest => NewsStrings.publishAndSendSelf,
        NewsNotificationAudience.everyone => NewsStrings.publishAndSendEveryone,
        null => NewsStrings.selectRecipients,
      };

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
        animation: _controller,
        builder: (context, _) => PopScope(
            canPop: !_saving && !_controller.isDirty,
            onPopInvokedWithResult: (didPop, _) {
              if (!didPop) _stornoPressed();
            },
            child: SafeArea(
              child: Scaffold(
                appBar: AppBar(
                  centerTitle: true,
                  title: Text(NewsStrings.createNews),
                  leading: BackButton(
                    onPressed: _saving ? null : _stornoPressed,
                  ),
                ),
                body: SingleChildScrollView(
                  child: Align(
                    alignment: Alignment.topCenter,
                    child: ConstrainedBox(
                      constraints:
                          BoxConstraints(maxWidth: StylesConfig.appMaxWidth),
                      child: Column(
                        children: [
                          Padding(
                            padding:
                                const EdgeInsets.symmetric(horizontal: 12.0),
                            child: FormBuilder(
                              key: _formKey,
                              child: Column(
                                children: [
                                  FormBuilderTextField(
                                    name: "heading",
                                    focusNode: _toFocusNode,
                                    decoration: InputDecoration(
                                        labelText: NewsStrings.heading,
                                        hintText: _currentUser?.name,
                                        floatingLabelBehavior:
                                            FloatingLabelBehavior.always),
                                  ),
                                  NewsNotificationAudienceSelector(
                                    selected: _audience,
                                    currentUserIdentity: _currentUserIdentity,
                                    allowEveryone: !AppConfig
                                        .isPublicNotificationSendingDisabled,
                                    onChanged: (value) =>
                                        setState(() => _audience = value),
                                  ),
                                  const SizedBox(height: 12),
                                ],
                              ),
                            ),
                          ),
                          widget.editorOverride ??
                              RichHtmlEditor(
                                  controller: _controller, enabled: !_saving),
                          if (_publishOutcomeUnknown)
                            Padding(
                                padding: const EdgeInsets.all(12),
                                child: Text(HtmlStrings.unknownPublish)),
                          _NewsFormActions(
                            onCancel: _saving ? () {} : _stornoPressed,
                            onPublish: _saving ||
                                    _confirming ||
                                    _publishOutcomeUnknown ||
                                    _audience == null
                                ? null
                                : _sendPressed,
                            publishLabel: _publishButtonText,
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            )));
  }
}

class _NewsFormActions extends StatelessWidget {
  final VoidCallback onCancel;
  final VoidCallback? onPublish;
  final String publishLabel;

  const _NewsFormActions({
    required this.onCancel,
    required this.onPublish,
    required this.publishLabel,
  });

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
      child: SizedBox(
        width: double.infinity,
        child: Wrap(
          alignment: WrapAlignment.end,
          crossAxisAlignment: WrapCrossAlignment.center,
          spacing: 12,
          runSpacing: 8,
          children: [
            TextButton(
              onPressed: onCancel,
              style: TextButton.styleFrom(
                foregroundColor: colors.onSurfaceVariant,
                padding: const EdgeInsets.symmetric(
                  horizontal: 18,
                  vertical: 14,
                ),
              ),
              child: Text(CommonStrings.storno),
            ),
            ElevatedButton.icon(
              onPressed: onPublish,
              icon: const Icon(Icons.publish_outlined, size: 20),
              label: Text(publishLabel),
              style: ElevatedButton.styleFrom(
                backgroundColor: colors.primary,
                foregroundColor: colors.onPrimary,
                disabledBackgroundColor: colors.onSurface.withAlpha(30),
                disabledForegroundColor: colors.onSurface.withAlpha(95),
                elevation: onPublish == null ? 0 : 2,
                padding: const EdgeInsets.symmetric(
                  horizontal: 20,
                  vertical: 14,
                ),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
