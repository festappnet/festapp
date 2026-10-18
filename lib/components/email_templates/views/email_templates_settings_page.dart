import 'dart:async';
import 'dart:convert';
import 'package:festapp_core/email_templates.dart';
import 'package:super_editor/super_editor.dart';
import '../email_authoring_provider.dart';
import '../email_preview_examples.dart';
import '../email_preview_html.dart';
import '../../html/rich_html_editor.dart';
import 'package:fstapp/data_services/rights_service.dart';
import 'package:fstapp/widgets/app_dialog.dart';
import 'package:fstapp/services/exception_handler.dart';
import 'package:flutter/material.dart';
import 'package:fstapp/components/email_templates/email_template_model.dart';
import 'package:fstapp/components/email_templates/db_email_templates.dart';
import 'package:fstapp/components/email_templates/email_templates_strings.dart';
import 'package:fstapp/services/dialog_helper.dart';
import 'package:fstapp/components/_shared/common_strings.dart';

import 'package:fstapp/components/html/rich_html_editor_controller.dart';
import 'package:fstapp/components/html/editable_html_field.dart';
import 'package:fstapp/services/toast_helper.dart';
import 'package:fstapp/widgets/info_tooltip_button.dart';

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
  late final RichHtmlEditorController _subjectEditor;
  late final EmailAuthoringProvider _subjectProvider;
  late final EmailAuthoringProvider _bodyProvider;
  RichHtmlEditorController? _bodyDraft;
  List<EmailPreviewScenario> _scenarios = [];
  EmailPreviewScenario? _scenario;
  bool _previewError = false;
  bool _contextUnavailable = false;
  bool _usesOccasionProducts = false;
  Timer? _suggestTimer;
  bool _dismissSuggestions = false;
  ({
    RichHtmlEditorController controller,
    int revision,
    String nodeId,
    EmailTitleMatch match,
    String code
  })? _suggestion;
  Future<void> _loadExamples() async {
    try {
      final examples = await EmailPreviewExamples.loadForOccasion(
          widget.emailTemplatesResponse.occasion);
      if (!mounted) return;
      setState(() {
        _scenarios = examples.scenariosFor(widget.template.code ?? '');
        _scenario = _scenarios.firstOrNull;
        _subjectProvider.scenario = _scenario;
        _bodyProvider.scenario = _scenario;
        _previewError = false;
        _contextUnavailable = examples.contextUnavailable;
        _usesOccasionProducts = examples.usesOccasionProducts;
      });
      _subjectEditor.refreshAuthoringPresentation();
      _bodyDraft?.refreshAuthoringPresentation();
    } catch (_) {
      if (mounted) setState(() => _previewError = true);
    }
  }

  void _draftUpdated(RichHtmlEditorController controller) {
    _htmlSave.draftChanged();
    _suggestTimer?.cancel();
    if (_suggestion != null) setState(() => _suggestion = null);
    if (_dismissSuggestions ||
        controller.revision == 0 ||
        !controller.focusNode.hasFocus) return;
    final title = widget.emailTemplatesResponse.occasion?.title;
    final code = widget.template.substitutions
        .map((s) => s.code)
        .where((code) => code == 'occasionTitle' || code == 'occasion_title')
        .firstOrNull;
    if (title == null || code == null) return;
    _suggestTimer = Timer(const Duration(milliseconds: 600), () {
      if (!mounted ||
          controller.editor.composer.composingRegion.value != null ||
          !controller.focusNode.hasFocus) return;
      final selection = controller.editor.composer.selection;
      if (selection == null || !selection.isCollapsed) return;
      final node =
          controller.editor.document.getNodeById(selection.extent.nodeId);
      if (node is! TextNode) return;
      final text = node.text.toPlainText();
      final caret = (selection.extent.nodePosition as TextNodePosition).offset;
      for (final match in EmailTemplateRules.titleMatches(text, title)) {
        if (caret < match.start || caret > match.end + 1) continue;
        if (List.generate(match.end - match.start,
                (i) => node.text.getAllAttributionsAt(match.start + i))
            .any((attrs) =>
                attrs.any((a) => a is LinkAttribution || a == codeAttribution)))
          continue;
        setState(() => _suggestion = (
              controller: controller,
              revision: controller.revision,
              nodeId: node.id,
              match: match,
              code: code
            ));
        controller.refreshAuthoringPresentation();
        break;
      }
    });
  }

  void _withdrawSuggestionIfLeft() {
    final suggestion = _suggestion;
    if (suggestion == null) return;
    final selection = suggestion.controller.editor.composer.selection;
    final position = selection?.extent.nodePosition;
    if (selection == null ||
        !selection.isCollapsed ||
        selection.extent.nodeId != suggestion.nodeId ||
        position is! TextNodePosition ||
        position.offset < suggestion.match.start ||
        position.offset > suggestion.match.end + 1) {
      setState(() => _suggestion = null);
      suggestion.controller.refreshAuthoringPresentation();
    }
  }

  Widget _suggestionView() {
    final suggestion = _suggestion;
    if (suggestion == null) return const SizedBox.shrink();
    return Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(EmailTemplatesStrings.suggestTitle(suggestion.match.text)),
          Wrap(children: [
            TextButton(
                onPressed: () {
                  suggestion.controller.insertTemplateToken(suggestion.code,
                      expectedRevision: suggestion.revision,
                      expectedText: suggestion.match.text,
                      replacement: DocumentSelection(
                          base: DocumentPosition(
                              nodeId: suggestion.nodeId,
                              nodePosition: TextNodePosition(
                                  offset: suggestion.match.start)),
                          extent: DocumentPosition(
                              nodeId: suggestion.nodeId,
                              nodePosition: TextNodePosition(
                                  offset: suggestion.match.end))));
                  setState(() => _suggestion = null);
                },
                child: Text(EmailTemplatesStrings.replaceVariable)),
            TextButton(
                onPressed: () => setState(() {
                      _dismissSuggestions = true;
                      _suggestion = null;
                      suggestion.controller.refreshAuthoringPresentation();
                    }),
                child: Text(EmailTemplatesStrings.keepText))
          ]),
        ]));
  }

  String get _sampleOrigin => _usesOccasionProducts
      ? EmailTemplatesStrings.occasionSample
      : EmailTemplatesStrings.modelSample;

  Widget _sampleControls({VoidCallback? onChanged}) =>
      Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        if (_scenario != null)
          Text(_sampleOrigin, style: Theme.of(context).textTheme.bodySmall),
        if (_contextUnavailable || _previewError)
          Wrap(crossAxisAlignment: WrapCrossAlignment.center, children: [
            Text(_previewError
                ? EmailTemplatesStrings.previewUnavailable
                : EmailTemplatesStrings.contextUnavailable),
            IconButton(
                tooltip: MaterialLocalizations.of(context)
                    .refreshIndicatorSemanticLabel,
                onPressed: _loadExamples,
                icon: const Icon(Icons.refresh)),
          ]),
        if (_scenarios.length > 1) const SizedBox(height: 8),
        if (_scenarios.length > 1)
          DropdownButtonFormField<EmailPreviewScenario>(
              value: _scenario,
              isExpanded: true,
              decoration: InputDecoration(
                  labelText: EmailTemplatesStrings.scenario,
                  isDense: true,
                  border: const OutlineInputBorder()),
              items: _scenarios
                  .map((s) => DropdownMenuItem(
                      value: s,
                      child: Text(
                          '${EmailTemplatesStrings.scenarioName(s.scenario)} · ${s.locale == 'cs' ? 'Čeština' : 'English'} · ${EmailTemplatesStrings.toneName(s.tone)}',
                          overflow: TextOverflow.ellipsis)))
                  .toList(),
              onChanged: (value) {
                if (value == null) return;
                setState(() {
                  _scenario = value;
                  _subjectProvider.scenario = value;
                  _bodyProvider.scenario = value;
                });
                _subjectEditor.refreshAuthoringPresentation();
                _bodyDraft?.refreshAuthoringPresentation();
                onChanged?.call();
              }),
      ]);

  Future<void> _showVariableHelp() => showDialog<void>(
      context: context,
      builder: (context) => AppAlertDialog(
          insetPadding: const EdgeInsets.symmetric(horizontal: 8, vertical: 24),
          contentPadding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
          title: Text(EmailTemplatesStrings.variableGuide),
          onClose: () => Navigator.pop(context),
          content: SizedBox(
              width: 640,
              child: SingleChildScrollView(
                  child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                    Text(EmailTemplatesStrings.variableGuideHint),
                    const SizedBox(height: 12),
                    for (final entry in _bodyProvider.search('', const {}))
                      ExpansionTile(
                          tilePadding: EdgeInsets.zero,
                          title: Text(entry.label),
                          subtitle: Text(entry.description),
                          childrenPadding: const EdgeInsets.only(bottom: 16),
                          expandedCrossAxisAlignment:
                              CrossAxisAlignment.stretch,
                          children: [
                            SelectableText('{{${entry.code}}}',
                                style: Theme.of(context).textTheme.labelMedium),
                            const SizedBox(height: 8),
                            Text(EmailTemplatesStrings.sampleData,
                                style: Theme.of(context).textTheme.labelMedium),
                            const SizedBox(height: 8),
                            if (entry.rich)
                              _bodyProvider.preview(context, entry.code) ??
                                  const SizedBox.shrink()
                            else
                              Text(entry.example),
                          ]),
                  ])))));

  Future<void> _showPreview() async {
    if (_previewError || _scenario == null) {
      await _loadExamples();
      if (!mounted || _scenario == null) return;
    }
    await showDialog<void>(
        context: context,
        builder: (context) => StatefulBuilder(
            builder: (context, update) => AppAlertDialog(
                  onClose: () => Navigator.pop(context),
                  insetPadding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 24),
                  contentPadding: const EdgeInsets.fromLTRB(16, 16, 16, 16),
                  title: Text(EmailTemplatesStrings.preview),
                  content: SizedBox(
                      width: 480,
                      child: SingleChildScrollView(
                          child: Column(
                              crossAxisAlignment: CrossAxisAlignment.stretch,
                              children: [
                            Text(EmailTemplatesStrings.previewScope),
                            _sampleControls(onChanged: () => update(() {})),
                            const SizedBox(height: 16),
                            EmailReceivedMessage(
                                subject: _scenario!.composeSubject(_subjectEditor.plainText),
                                html: _scenario!.composeHtml(_bodyDraft?.html ?? _htmlContent ?? ''),
                                imageBytesResolver: _htmlSave.media.previewBytes),
                          ]))),
                )));
  }

  bool get _canEdit => widget.emailTemplatesResponse.occasion != null
      ? RightsService.canEditOccasion() || RightsService.isOrderEditor()
      : RightsService.isUnitEditor();
  @override
  Widget build(BuildContext context) => HtmlEditingScope(
      coordinator: _htmlSave, child: _buildHtmlParent(context));
  @override
  void dispose() {
    _suggestTimer?.cancel();
    _subjectEditor.dispose();
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
    _subjectProvider = EmailAuthoringProvider(widget.template,
        field: EmailTargetField.subject);
    _bodyProvider =
        EmailAuthoringProvider(widget.template, field: EmailTargetField.body);
    _subjectEditor = RichHtmlEditorController(
        initialHtml: '<p>${htmlEscape.convert(_subject ?? '')}</p>',
        owner: const HtmlMediaOwner.none(),
        authoring: _subjectProvider);
    _subjectProvider.onSelectionChanged = _withdrawSuggestionIfLeft;
    _bodyProvider.onSelectionChanged = _withdrawSuggestionIfLeft;
    _subjectProvider.footerBuilder = (_) =>
        _suggestion?.controller == _subjectEditor
            ? _suggestionView()
            : const SizedBox.shrink();
    _bodyProvider.footerBuilder = (_) => _suggestion?.controller == _bodyDraft
        ? _suggestionView()
        : const SizedBox.shrink();
    _subjectEditor.addListener(() {
      _subject = _subjectEditor.plainText;
      _draftUpdated(_subjectEditor);
    });
    _htmlSave.registerActive(
        _subjectEditor, () => _subject = _subjectEditor.plainText,
        isDirty: () => _subjectEditor.hasUserChanges,
        acceptSave: () => _subjectEditor.reset(_subjectEditor.html));
    _loadExamples();
  }

  Future<void> _saveSettings() async {
    if (!_canEdit) return;
    await ExceptionHandler.guardVoid(context,
        futureFunction: () =>
            _htmlSave.save(() => _performHtmlSave(), context: context));
  }

  Future<void> _performHtmlSave() async {
    if (!_canEdit) return;
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

  Widget _buildHtmlParent(BuildContext context) {
    // Get usage details from the email template (read-only info).
    final usageDetails = widget.template.getUsageDetails();
    return AppAlertDialog(
      onClose: () async {
        if (await confirmHtmlDiscard(context, _htmlSave) && context.mounted)
          Navigator.of(context).pop();
      },
      title: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Expanded(
            child: Text(
              usageDetails['title'] ?? '',
              style: const TextStyle(fontSize: 20),
            ),
          ),
        ],
      ),
      insetPadding: EdgeInsets.symmetric(
          horizontal: MediaQuery.sizeOf(context).width < 600 ? 8 : 40,
          vertical: 24),
      contentPadding: EdgeInsets.fromLTRB(
          MediaQuery.sizeOf(context).width < 600 ? 12 : 24,
          16,
          MediaQuery.sizeOf(context).width < 600 ? 12 : 24,
          0),
      actionsPadding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
      content: SizedBox(
        width: 760,
        child: Form(
          key: _formKey,
          child: ListView(
            shrinkWrap: true,
            children: [
              Text(usageDetails['description'] ?? '',
                  style: Theme.of(context).textTheme.bodyMedium),
              const SizedBox(height: 8),
              Text(EmailTemplatesStrings.authoringHint,
                  style: Theme.of(context).textTheme.bodySmall),
              Wrap(
                  spacing: 8,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    TextButton.icon(
                        onPressed: _showVariableHelp,
                        icon: const Icon(Icons.info_outline),
                        label: Text(EmailTemplatesStrings.variableGuide)),
                    TextButton.icon(
                        onPressed: _showPreview,
                        icon: const Icon(Icons.preview_outlined),
                        label: Text(EmailTemplatesStrings.preview)),
                  ]),
              _sampleControls(),
              const SizedBox(height: 16),
              Text(EmailTemplatesStrings.subject,
                  style: Theme.of(context).textTheme.labelLarge),
              const SizedBox(height: 8),
              // Subject text field.
              FormField<String>(
                  validator: (_) => _subjectEditor.plainText.trim().isEmpty
                      ? EmailTemplatesStrings.subjectRequired
                      : null,
                  builder: (field) => InputDecorator(
                      decoration: InputDecoration(
                          isDense: true,
                          border: const OutlineInputBorder(),
                          contentPadding: const EdgeInsets.symmetric(
                              horizontal: 8, vertical: 2),
                          filled: true,
                          fillColor: Theme.of(context).colorScheme.surface,
                          errorText: field.errorText),
                      child: Semantics(
                          label: EmailTemplatesStrings.subject,
                          textField: true,
                          enabled: _canEdit,
                          onTap: _canEdit
                              ? _subjectEditor.focusNode.requestFocus
                              : null,
                          child: RichHtmlEditor(
                              controller: _subjectEditor, enabled: _canEdit)))),
              const SizedBox(height: 16),
              Text(EmailTemplatesStrings.emailTemplateContent,
                  style: Theme.of(context).textTheme.labelLarge),
              const SizedBox(height: 8),
              DecoratedBox(
                  decoration: BoxDecoration(
                      color: Theme.of(context).colorScheme.surface,
                      border: Border.all(
                          color: Theme.of(context).colorScheme.outlineVariant),
                      borderRadius: BorderRadius.circular(8)),
                  child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 8),
                      child: EditableHtmlField(
                          enabled: _canEdit,
                          authoring: _bodyProvider,
                          onDraftChanged: (controller) {
                            _bodyDraft = controller;
                            if (controller != null) _draftUpdated(controller);
                          },
                          html: _htmlContent,
                          coordinator: _htmlSave,
                          profile: HtmlContentProfile.emailContent,
                          owner: widget.emailTemplatesResponse.occasion?.id !=
                                  null
                              ? HtmlMediaOwner.occasion(
                                  widget.emailTemplatesResponse.occasion!.id)
                              : HtmlMediaOwner.unit(
                                  widget.emailTemplatesResponse.unit.id),
                          onChanged: (html) =>
                              setState(() => _htmlContent = html)))),
              const SizedBox(height: 16),
            ],
          ),
        ),
      ),
      actions: [
        AppDialogActions(
          leading: _canEdit &&
                  ((widget.template.occasion != null &&
                          widget.template.occasion ==
                              widget.emailTemplatesResponse.occasion?.id) ||
                      (widget.template.unit != null &&
                          widget.template.unit ==
                              widget.emailTemplatesResponse.unit.id &&
                          widget.emailTemplatesResponse.occasion == null))
              ? TextButton(
                  onPressed: () async {
                    final confirmed = await DialogHelper.showConfirmationDialog(
                      context,
                      EmailTemplatesStrings.resetConfirmTitle,
                      EmailTemplatesStrings.resetConfirmContent,
                      confirmButtonMessage:
                          EmailTemplatesStrings.resetToDefault,
                    );

                    if (confirmed == true) {
                      await DbEmailTemplates.deleteEntityEmailTemplate(
                        occasionId: widget.emailTemplatesResponse.occasion?.id,
                        unitId: widget.emailTemplatesResponse.occasion == null
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
              : Row(
                  children: [
                    Flexible(
                      child: Text(
                        EmailTemplatesStrings.defaultTemplateInUse,
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                    ),
                    InfoTooltipButton(
                      message: EmailTemplatesStrings.defaultTemplateInfo,
                      semanticLabel: EmailTemplatesStrings.defaultTemplateInfo,
                      color: Theme.of(context).colorScheme.onSurface,
                    ),
                  ],
                ),
          actions: [
            TextButton(
              onPressed: () async {
                if (await confirmHtmlDiscard(context, _htmlSave) &&
                    context.mounted) Navigator.of(context).pop();
              },
              child: Text(CommonStrings.storno),
            ),
            const SizedBox(width: 8),
            FilledButton(
              onPressed: _canEdit ? _saveSettings : null,
              child: Text(CommonStrings.save),
            ),
          ],
        ),
      ],
    );
  }
}
