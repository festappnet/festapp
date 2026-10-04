import 'package:fstapp/services/exception_handler.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:form_builder_validators/form_builder_validators.dart';
import 'package:fstapp/components/email_templates/email_template_model.dart';
import 'package:fstapp/components/email_templates/db_email_templates.dart';
import 'package:fstapp/components/email_templates/email_templates_strings.dart';
import 'package:fstapp/services/dialog_helper.dart';
import 'package:fstapp/components/_shared/common_strings.dart';

import 'package:fstapp/components/html/rich_html_editor_controller.dart';
import 'package:fstapp/components/html/editable_html_field.dart';
import 'package:fstapp/services/toast_helper.dart';
import 'package:fstapp/theme_config.dart';
import 'package:fstapp/styles/styles_config.dart';

class EmailTemplateSettingsPage extends StatefulWidget {
  final EmailTemplateModel template;
  final EmailTemplatesResponse emailTemplatesResponse;

  const EmailTemplateSettingsPage({
    super.key,
    required this.template,
    required this.emailTemplatesResponse,
  });

  @override
  _EmailTemplateSettingsPageState createState() =>
      _EmailTemplateSettingsPageState();
}

class _EmailTemplateSettingsPageState extends State<EmailTemplateSettingsPage> {
  final _htmlSave = HtmlSaveCoordinator();
  @override
  Widget build(BuildContext context) => HtmlEditingScope(
      coordinator: _htmlSave, child: _buildHtmlParent(context));
  @override
  void dispose() {
    _htmlSave.dispose();
    super.dispose();
  }

  final _formKey = GlobalKey<FormState>();
  late String? _subject;
  late String? _htmlContent;

  @override
  void initState() {
    super.initState();
    _subject = widget.template.subject;
    _htmlContent = widget.template.html;
  }

  Future<void> _saveSettings() async {
    await ExceptionHandler.guardVoid(context,
        futureFunction: () =>
            _htmlSave.save(() => _performHtmlSave(), context: context));
  }

  Future<void> _performHtmlSave() async {
    if (_formKey.currentState?.validate() ?? false) {
      _formKey.currentState!.save();
      _htmlContent = await _htmlSave.prepare(
          _htmlContent ?? '',
          widget.emailTemplatesResponse.occasion?.id != null
              ? HtmlMediaOwner.occasion(
                  widget.emailTemplatesResponse.occasion!.id)
              : HtmlMediaOwner.unit(widget.emailTemplatesResponse.unit.id));
      widget.template.subject = _subject;
      widget.template.html = _htmlContent;

      // Set the integer fields from the emailTemplatesResponse if available.
      widget.template.occasion = widget.emailTemplatesResponse.occasion?.id;
      widget.template.unit = widget.emailTemplatesResponse.unit.id;
      widget.template.organization =
          widget.emailTemplatesResponse.organization.id;

      await DbEmailTemplates.updateEmailTemplate(widget.template);
      _htmlSave.markSaved();
      ToastHelper.Show(
          context, "${CommonStrings.saved}: ${widget.template.subject ?? ''}");
      Navigator.of(context).pop();
    }
  }

  /// Builds a widget displaying the available substitutions.
  /// If [subs] is a list, each substitution is shown on its own line.
  Widget _buildSubsDefinition(dynamic subs) {
    if (subs == null) return const SizedBox();
    if (subs is List) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: subs.map<Widget>((sub) {
          if (sub is EmailTemplateSub) {
            return Text(
              "{{${sub.code}}}: ${sub.description}",
              style: const TextStyle(fontSize: 14),
            );
          }
          return const SizedBox();
        }).toList(),
      );
    } else if (subs is String) {
      return Text(
        subs,
        style: const TextStyle(fontSize: 14),
        maxLines: 2,
        overflow: TextOverflow.ellipsis,
      );
    } else if (subs is Map<String, dynamic>) {
      final subsText = subs.entries
          .map((entry) => "${entry.key}: ${entry.value}".tr())
          .join("\n");
      return Text(
        subsText,
        style: const TextStyle(fontSize: 14),
        maxLines: 3,
        overflow: TextOverflow.ellipsis,
      );
    }
    return const SizedBox();
  }

  Widget _buildHtmlParent(BuildContext context) {
    // Get usage details from the email template (read-only info).
    final usageDetails = widget.template.getUsageDetails();
    return AlertDialog(
      title: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Expanded(
            child: Text(
              usageDetails['title'] ?? '',
              style: const TextStyle(fontSize: 20),
            ),
          ),
          IconButton(
            icon: const Icon(Icons.close),
            onPressed: () async {
              if (await confirmHtmlDiscard(context, _htmlSave) &&
                  context.mounted) Navigator.of(context).pop();
            },
          )
        ],
      ),
      contentPadding: const EdgeInsets.fromLTRB(24, 20, 24, 0),
      actionsPadding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
      content: SizedBox(
        width: StylesConfig.formMaxWidth, // Use max available width in dialog
        child: Form(
          key: _formKey,
          child: ListView(
            shrinkWrap: true,
            children: [
              // Usage details container wrapped in a SelectionArea.
              SelectionArea(
                child: Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: ThemeConfig.grey150(context),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: ThemeConfig.grey300(context)),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        usageDetails['title'] ?? '',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                            fontSize: 14, fontWeight: FontWeight.bold),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        usageDetails['description'] ?? '',
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 14,
                          color: ThemeConfig.grey850(context),
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        EmailTemplatesStrings.availableSubstitutions,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                            fontSize: 14, fontWeight: FontWeight.bold),
                      ),
                      const SizedBox(height: 4),
                      _buildSubsDefinition(usageDetails['subs']),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 16),
              // Subject text field.
              TextFormField(
                initialValue: _subject,
                decoration:
                    InputDecoration(labelText: EmailTemplatesStrings.subject),
                validator: FormBuilderValidators.compose([
                  FormBuilderValidators.required(
                      errorText: EmailTemplatesStrings.subjectRequired),
                ]),
                onSaved: (val) => _subject = val,
                style: TextStyle(
                  color: ThemeConfig.grey850(context),
                ),
              ),
              const SizedBox(height: 16),
              // Email Template Content Section header.
              Container(
                padding: const EdgeInsets.symmetric(vertical: 8.0),
                decoration: BoxDecoration(
                  border: Border(
                    bottom: BorderSide(
                      color: ThemeConfig.grey300(context),
                      width: 1.0,
                    ),
                  ),
                ),
                child: Text(
                  EmailTemplatesStrings.emailTemplateContent,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                    color: Theme.of(context)
                            .inputDecorationTheme
                            .labelStyle
                            ?.color ??
                        ThemeConfig.grey700(context).withOpacity(0.85),
                  ),
                ),
              ),
              const SizedBox(height: 8),
              EditableHtmlField(
                  html: _htmlContent,
                  coordinator: _htmlSave,
                  profile: HtmlContentProfile.emailContent,
                  owner: widget.emailTemplatesResponse.occasion?.id != null
                      ? HtmlMediaOwner.occasion(
                          widget.emailTemplatesResponse.occasion!.id)
                      : HtmlMediaOwner.unit(
                          widget.emailTemplatesResponse.unit.id),
                  onChanged: (html) => setState(() => _htmlContent = html)),
              const SizedBox(height: 8),
              const SizedBox(height: 16),
            ],
          ),
        ),
      ),
      actions: [
        Row(
          children: [
            Expanded(
              child: Align(
                alignment: Alignment.centerLeft,
                child: ((widget.template.occasion != null &&
                            widget.template.occasion ==
                                widget.emailTemplatesResponse.occasion?.id) ||
                        (widget.template.unit != null &&
                            widget.template.unit ==
                                widget.emailTemplatesResponse.unit.id &&
                            widget.emailTemplatesResponse.occasion == null))
                    ? TextButton(
                        onPressed: () async {
                          final confirmed =
                              await DialogHelper.showConfirmationDialog(
                            context,
                            EmailTemplatesStrings.resetConfirmTitle,
                            EmailTemplatesStrings.resetConfirmContent,
                            confirmButtonMessage:
                                EmailTemplatesStrings.resetToDefault,
                          );

                          if (confirmed == true) {
                            await DbEmailTemplates.deleteEntityEmailTemplate(
                              occasionId:
                                  widget.emailTemplatesResponse.occasion?.id,
                              unitId:
                                  widget.emailTemplatesResponse.occasion == null
                                      ? widget.emailTemplatesResponse.unit.id
                                      : null,
                              code: widget.template.code!,
                            );

                            if (context.mounted) {
                              Navigator.of(context).pop();
                            }
                          }
                        },
                        child: Text(EmailTemplatesStrings.resetToDefault),
                      )
                    : null,
              ),
            ),
            TextButton(
              onPressed: () async {
                if (await confirmHtmlDiscard(context, _htmlSave) &&
                    context.mounted) Navigator.of(context).pop();
              },
              child: Text(CommonStrings.storno),
            ),
            const SizedBox(width: 8),
            ElevatedButton(
              onPressed: _saveSettings,
              child: Text(CommonStrings.save),
            ),
          ],
        ),
      ],
    );
  }
}
