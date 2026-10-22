import 'package:fstapp/data_services/authorization_capabilities.dart';
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
  final Future<EmailAuthoringContext> Function()? authoringContextLoader;
  final Future<EmailPreviewExamples> Function()? previewExamplesLoader;
  final Future<void> Function(EmailTemplateModel)? saveTemplate;
  final Future<void> Function()? resetTemplate;

  const EmailTemplateSettingsPage({
    super.key,
    required this.template,
    required this.emailTemplatesResponse,
    this.authoringContextLoader,
    this.previewExamplesLoader,
    this.saveTemplate,
    this.resetTemplate,
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
  EmailPreviewExamples? _examples;
  List<EmailPreviewScenario> _scenarios = [];
  EmailPreviewScenario? _scenario;
  bool _previewError = false;
  EmailAuthoringContext? _authoringContext;
  late final Future<void> _initialAuthoringContext;
  bool _authoringContextLoading = false;
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
  Future<void> _loadAuthoringContext() async {
    _authoringContextLoading = true;
    try {
      final value = await (widget.authoringContextLoader?.call() ??
          DbEmailTemplates.getAuthoringContext(
              widget.emailTemplatesResponse, widget.template.code ?? ''));
      if (mounted) {
        _authoringContext = value;
        _refreshScenarios();
        _subjectEditor.refreshAuthoringPresentation();
      }
    } catch (_) {
      if (mounted) _authoringContext = null;
    } finally {
      _authoringContextLoading = false;
      if (mounted) {
        setState(() {});
        _bodyDraft?.refreshAuthoringPresentation();
      }
    }
  }

  Future<void> _loadExamples() async {
    try {
      final examples = await (widget.previewExamplesLoader?.call() ??
          EmailPreviewExamples.loadForOccasion(
              widget.emailTemplatesResponse.occasion));
      if (!mounted) return;
      setState(() {
        _examples = examples;
        _refreshScenarios();
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

  void _refreshScenarios() {
    final examples = _examples;
    if (examples == null) return;
    final previous = _scenario;
    _scenarios = examples.scenariosFor(widget.template.code ?? '',
        paymentAccounts: _authoringContext?.paymentAccounts ?? const []);
    _scenario = _scenarios
            .where((s) =>
                s.scenario == previous?.scenario &&
                s.locale == previous?.locale &&
                s.tone == previous?.tone)
            .firstOrNull ??
        _scenarios.firstOrNull;
    _subjectProvider.scenario = _scenario;
    _bodyProvider.scenario = _scenario;
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
                onPressed: () async {
                  await _loadExamples();
                  onChanged?.call();
                },
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

  String _scenarioLabel(EmailPreviewScenario scenario) =>
      '${EmailTemplatesStrings.scenarioName(scenario.scenario)} · ${scenario.locale == 'cs' ? 'Čeština' : 'English'} · ${EmailTemplatesStrings.toneName(scenario.tone)}';

  Future<void> _showSampleSettings() => showDialog<void>(
      context: context,
      builder: (context) => StatefulBuilder(
          builder: (context, update) => AppAlertDialog(
                title: Text(EmailTemplatesStrings.scenario),
                onClose: () => Navigator.pop(context),
                insetPadding:
                    const EdgeInsets.symmetric(horizontal: 8, vertical: 24),
                content: SizedBox(
                    width: 440,
                    child: _sampleControls(onChanged: () {
                      if (context.mounted) update(() {});
                    })),
              )));

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
                    Text(EmailTemplatesStrings.authoringHint),
                    const SizedBox(height: 8),
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
    await _initialAuthoringContext;
    if (!mounted) return;
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
                            if (_authoringContext != null)
                              Text(EmailTemplatesStrings.previewScope)
                            else ...[
                              Text(EmailTemplatesStrings
                                  .authoringContextUnavailable),
                              if (_authoringContextLoading)
                                const LinearProgressIndicator()
                              else
                                TextButton.icon(
                                    icon: const Icon(Icons.refresh),
                                    label: Text(CommonStrings.retry),
                                    onPressed: () async {
                                      final request = _loadAuthoringContext();
                                      update(() {});
                                      await request;
                                      if (context.mounted) update(() {});
                                    }),
                            ],
                            _sampleControls(onChanged: () => update(() {})),
                            const SizedBox(height: 16),
                            if (_authoringContext != null)
                              EmailReceivedMessage(
                                  senderAddress:
                                      _authoringContext!.senderAddress,
                                  allowedRemoteImageSources:
                                      _authoringContext!.bannerImageSources,
                                  subject: _scenario!
                                      .composeSubject(_subjectEditor.plainText),
                                  html: _authoringContext!.composeHtml(
                                      _scenario!,
                                      _bodyDraft?.html ?? _htmlContent ?? ''),
                                  imageBytesResolver:
                                      _htmlSave.media.previewBytes),
                          ]))),
                )));
  }

  bool get _canEdit =>
      widget.saveTemplate != null ||
      (widget.emailTemplatesResponse.occasion != null
          ? RightsService.hasCapability(
              AuthorizationCapabilities.emailTemplatesOccasionWrite)
          : RightsService.hasCapability(
              AuthorizationCapabilities.emailTemplatesUnitWrite));
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
    _bodyProvider.completion = _authoringCompletion;
    _bodyProvider.headerBuilder = (_) => _bodyLeading();
    _subjectProvider.onSelectionChanged = _withdrawSuggestionIfLeft;
    _bodyProvider.onSelectionChanged = _withdrawSuggestionIfLeft;
    _subjectProvider.footerBuilder = (_) =>
        _suggestion?.controller == _subjectEditor
            ? _suggestionView()
            : const SizedBox.shrink();
    _bodyProvider.footerBuilder = (_) {
      final draft = _bodyDraft;
      return draft == null
          ? _bodyFooter()
          : ListenableBuilder(
              listenable: draft,
              builder: (context, _) => _bodyFooter(),
            );
    };
    _subjectEditor.addListener(() {
      _subject = _subjectEditor.plainText;
      _draftUpdated(_subjectEditor);
    });
    _htmlSave.registerActive(
        _subjectEditor, () => _subject = _subjectEditor.plainText,
        isDirty: () => _subjectEditor.hasUserChanges,
        acceptSave: () => _subjectEditor.reset(_subjectEditor.html));
    _loadExamples();
    _initialAuthoringContext = _loadAuthoringContext();
  }

  EmailAuthoringCompletion? _authoringCompletion() => _authoringContext == null
      ? null
      : _scenario?.authoringCompletion(_bodyDraft?.html ?? _htmlContent ?? '',
          wrapperHtml: _authoringContext!.wrapperHtml);

  Widget _bodyLeading() {
    Widget render() {
      final html = _authoringCompletion()?.leadingHtml ?? '';
      return html.isEmpty
          ? const SizedBox.shrink()
          : Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8),
              child: EmailPreviewHtml(
                  key: const ValueKey('email-automatic-leading'), html: html));
    }

    return _bodyProvider.previewChanges == null
        ? render()
        : ListenableBuilder(
            listenable: _bodyProvider.previewChanges!,
            builder: (context, child) => render());
  }

  Future<void> _requestClose() async {
    if (await confirmHtmlDiscard(context, _htmlSave) && mounted)
      Navigator.of(context).pop();
  }

  Widget _bodyFooter() {
    // Wait for the authoritative wrapper before deciding whether delivery adds
    // a link. This is presentation only, outside the editable document.
    final automatic = _authoringCompletion()?.trailingHtml ?? '';
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (automatic.isNotEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8),
            child: EmailPreviewHtml(
              key: const ValueKey('email-automatic-completion'),
              html: automatic,
            ),
          ),
        if (_suggestion?.controller == _bodyDraft) _suggestionView(),
      ],
    );
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

      await (widget.saveTemplate?.call(widget.template) ??
          DbEmailTemplates.updateEmailTemplate(widget.template));
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
      onClose: _requestClose,
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
      actionsPadding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
      content: SizedBox(
        width: 760,
        child: Form(
          key: _formKey,
          child: ListView(
            shrinkWrap: true,
            children: [
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Theme.of(context).colorScheme.surfaceContainerLow,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(
                      color: Theme.of(context).colorScheme.outlineVariant),
                ),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Padding(
                      padding: const EdgeInsets.only(top: 2),
                      child: Icon(Icons.info_outline,
                          size: 20,
                          color: Theme.of(context).colorScheme.primary),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                        child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(EmailTemplatesStrings.whenSent,
                            style: Theme.of(context).textTheme.labelLarge),
                        const SizedBox(height: 4),
                        Text(usageDetails['description'] ?? '',
                            style: Theme.of(context).textTheme.bodyMedium),
                      ],
                    )),
                  ],
                ),
              ),
              const SizedBox(height: 16),
              Row(children: [
                Expanded(
                    child: Text(EmailTemplatesStrings.subject,
                        style: Theme.of(context).textTheme.labelLarge)),
                if (MediaQuery.sizeOf(context).width < 480)
                  IconButton(
                      onPressed: _showPreview,
                      tooltip: EmailTemplatesStrings.preview,
                      icon: const Icon(Icons.preview_outlined, size: 20))
                else
                  Tooltip(
                      message: EmailTemplatesStrings.preview,
                      child: TextButton.icon(
                          onPressed: _showPreview,
                          icon: const Icon(Icons.preview_outlined, size: 20),
                          label: Text(EmailTemplatesStrings.previewShort))),
              ]),
              // Subject text field.
              FormField<String>(
                  validator: (_) => _subjectEditor.plainText.trim().isEmpty
                      ? EmailTemplatesStrings.subjectRequired
                      : null,
                  builder: (field) => ListenableBuilder(
                      listenable: _subjectEditor.focusNode,
                      builder: (context, _) => InputDecorator(
                          isFocused: _subjectEditor.focusNode.hasFocus,
                          decoration: InputDecoration(
                              isDense: true,
                              border: const OutlineInputBorder(),
                              contentPadding:
                                  const EdgeInsets.only(left: 12, right: 4),
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
                                  controller: _subjectEditor,
                                  enabled: _canEdit,
                                  onCancel: _requestClose,
                                  textStyle: Theme.of(context)
                                      .textTheme
                                      .bodyLarge
                                      ?.copyWith(height: 1.5)))))),
              const SizedBox(height: 16),
              Row(children: [
                Expanded(
                    child: Text(EmailTemplatesStrings.emailTemplateContent,
                        style: Theme.of(context).textTheme.labelLarge)),
                IconButton(
                    onPressed: _showVariableHelp,
                    tooltip: EmailTemplatesStrings.variableGuide,
                    icon: const Icon(Icons.info_outline, size: 20)),
                IconButton(
                    onPressed: _showSampleSettings,
                    tooltip:
                        '${EmailTemplatesStrings.scenario}: $_sampleOrigin${_scenario == null ? '' : ' · ${_scenarioLabel(_scenario!)}'}',
                    icon: Icon(
                        _contextUnavailable || _previewError
                            ? Icons.warning_amber_outlined
                            : Icons.tune,
                        size: 20)),
              ]),
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
                          onCancel: _requestClose,
                          onDraftChanged: (controller) {
                            if (!identical(_bodyDraft, controller)) {
                              _bodyProvider.previewChanges = controller == null
                                  ? null
                                  : Listenable.merge([
                                      controller,
                                      controller.authoringChanges
                                    ]);
                            }
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
                  (widget.saveTemplate != null
                      ? widget.resetTemplate != null
                      : ((widget.template.occasion != null &&
                              widget.template.occasion ==
                                  widget.emailTemplatesResponse.occasion?.id) ||
                          (widget.template.unit != null &&
                              widget.template.unit ==
                                  widget.emailTemplatesResponse.unit.id &&
                              widget.emailTemplatesResponse.occasion == null)))
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
                      await (widget.resetTemplate?.call() ??
                          DbEmailTemplates.deleteEntityEmailTemplate(
                            occasionId:
                                widget.emailTemplatesResponse.occasion?.id,
                            unitId:
                                widget.emailTemplatesResponse.occasion == null
                                    ? widget.emailTemplatesResponse.unit.id
                                    : null,
                            code: widget.template.code!,
                          ));

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
              onPressed: _requestClose,
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
