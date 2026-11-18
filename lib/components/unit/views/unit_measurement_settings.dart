import 'package:flutter/foundation.dart' show setEquals;
import 'package:flutter/services.dart' show FilteringTextInputFormatter;

import '../unit_settings_fields.dart';

import 'package:fstapp/widgets/app_dialog.dart';

import 'package:festapp_core/forms.dart';
import 'package:fstapp/components/forms/form_strings.dart';
import 'package:fstapp/components/_shared/common_strings.dart';
import 'package:material_ui/material_ui.dart';
import 'package:intl/intl.dart';

import '../unit_measurement_approval.dart';
import 'unit_measurement_help.dart';

/// Destination configuration is independent of permission to run measurement.
/// The owning screen saves these fields through the canonical Unit aggregate.
class UnitMeasurementSettings extends StatelessWidget {
  final TextEditingController? websitesController;
  final bool enabled;
  final Widget Function()? websiteConsentBuilder;
  final bool consentBridge;
  final ValueChanged<bool>? onConsentBridgeChanged;
  final String consentLayout;
  final bool canEdit;
  final bool hasStoredTitle;
  final bool hasStoredText;
  final ValueChanged<TextEditingController>? onRestore;
  final TextEditingController gtmController;
  final TextEditingController scriptsController;
  final TextEditingController privacyUrlController;
  final TextEditingController consentTitleController;
  final TextEditingController consentTextController;
  final ValueChanged<bool> onEnabledChanged;
  final ValueChanged<String> onConsentLayoutChanged;
  final UnitMeasurementApproval? approval;
  final List<String> savedWebsites;
  final bool loadingApproval;
  final bool approvalLoadFailed;
  final VoidCallback? onRetryApproval;
  final bool requestingApproval;
  final VoidCallback? onRequestApproval;

  const UnitMeasurementSettings({
    super.key,
    required this.enabled,
    this.websiteConsentBuilder,
    this.websitesController,
    this.consentBridge = false,
    this.onConsentBridgeChanged,
    required this.consentLayout,
    required this.canEdit,
    this.hasStoredTitle = false,
    this.hasStoredText = false,
    this.onRestore,
    required this.gtmController,
    required this.scriptsController,
    required this.privacyUrlController,
    required this.consentTitleController,
    required this.consentTextController,
    required this.onEnabledChanged,
    required this.onConsentLayoutChanged,
    this.approval,
    this.savedWebsites = const [],
    this.loadingApproval = false,
    this.approvalLoadFailed = false,
    this.onRetryApproval,
    this.requestingApproval = false,
    this.onRequestApproval,
  });

  bool get _privacyUrlRequired =>
      enabled &&
      (gtmController.text.trim().isNotEmpty ||
          scriptsController.text.trim().isNotEmpty);

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: Listenable.merge([
      ?websitesController,
      gtmController,
      scriptsController,
      privacyUrlController,
      consentTitleController,
      consentTextController,
    ]),
    builder: (context, _) => _tile(context),
  );

  static List<String> parseWebsites(String text) => text
      .split('\n')
      .map((s) => s.trim())
      .where((s) => s.isNotEmpty)
      .map((site) {
        final uri = Uri.tryParse(site);
        if (uri != null &&
            uri.scheme == 'https' &&
            uri.host.isNotEmpty &&
            uri.userInfo.isEmpty &&
            uri.path.isEmpty &&
            !uri.hasQuery &&
            !uri.hasFragment) {
          return uri.origin;
        }
        return site;
      })
      .toSet()
      .toList();

  static String? validateWebsites(String? value) {
    final sites = parseWebsites(value ?? '');
    final pattern = RegExp(unitMeasurementWebsitePattern);
    return sites.length <= 10 &&
            sites.every((s) => s.length <= 2048 && pattern.hasMatch(s))
        ? null
        : FormStrings.measurementWebsitesInvalid;
  }

  Widget _tile(BuildContext context) {
    final theme = Theme.of(context);
    final sites = parseWebsites(websitesController?.text ?? '');
    final statusKnown =
        approval != null &&
        !loadingApproval &&
        !approvalLoadFailed &&
        approval!.requestState != MeasurementRequestState.unavailable;
    final unsaved =
        statusKnown &&
        websitesController != null &&
        !setEquals(sites.toSet(), approval!.savedOrigins.toSet());
    final platformStatus = !statusKnown
        ? FormStrings.measurementPlatformUnknown
        : !approval!.organizationAllowed
        ? FormStrings.measurementApprovalRequired
        : !approval!.runtimeSupported
        ? FormStrings.measurementRuntimePending
        : FormStrings.measurementPlatformPending;
    final sectionShape = Border(top: BorderSide(color: theme.dividerColor));
    final hintStyle = theme.textTheme.bodySmall?.copyWith(
      color: theme.colorScheme.onSurfaceVariant,
      height: 1.45,
    );
    const gap = SizedBox(height: 24);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            Chip(
              avatar: Icon(
                enabled
                    ? Icons.check_circle_outline
                    : Icons.pause_circle_outline,
                size: 18,
              ),
              label: Text(
                enabled
                    ? FormStrings.measurementOn
                    : FormStrings.measurementOff,
              ),
            ),
            if (privacyUrlController.text.trim().isNotEmpty)
              Chip(
                avatar: const Icon(Icons.check, size: 18),
                label: Text(FormStrings.measurementPolicySummary),
              ),
            if (gtmController.text.trim().isNotEmpty)
              const Chip(
                avatar: Icon(Icons.check, size: 18),
                label: Text('GTM'),
              ),
            if (approval?.approved != true)
              Chip(
                avatar: const Icon(Icons.info_outline, size: 18),
                label: Text(platformStatus),
              ),
          ],
        ),
        gap,
        UnitMeasurementSectionTitle(
          FormStrings.measurementBasics,
          UnitMeasurementHelp.basics,
          style: theme.textTheme.titleMedium,
        ),
        const SizedBox(height: 8),
        LayoutBuilder(
          builder: (context, constraints) {
            final wide = constraints.maxWidth >= 800;
            final fields = <Widget>[
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: Text(FormStrings.measurementUnitEnabled),
                subtitle: Text(FormStrings.measurementUnitHelp),
                value: enabled,
                onChanged: canEdit ? onEnabledChanged : null,
              ),
              TextFormField(
                key: const PageStorageKey("measurement-gtmController"),
                controller: gtmController,
                enabled: canEdit,
                maxLength: 36,
                maxLines: wide ? 1 : null,
                minLines: 1,
                decoration: InputDecoration(
                  labelText: FormStrings.gtmContainer,
                  suffixIcon: UnitMeasurementHelpButton(
                    UnitMeasurementHelp.gtm,
                    label: FormStrings.gtmContainer,
                  ),
                  hintText: 'GTM-XXXX',
                  helperText: FormStrings.gtmHelp,
                  helperMaxLines: 6,
                  border: const OutlineInputBorder(),
                ),
                validator: (value) =>
                    value == null ||
                        value.trim().isEmpty ||
                        RegExp(r'^GTM-[A-Z0-9]{4,32}$').hasMatch(value.trim())
                    ? null
                    : FormStrings.gtmInvalid,
              ),
              TextFormField(
                key: const PageStorageKey("measurement-privacyUrlController"),
                controller: privacyUrlController,
                enabled: canEdit,
                maxLength: 2048,
                maxLines: wide ? 1 : null,
                minLines: 1,
                keyboardType: TextInputType.url,
                decoration: InputDecoration(
                  labelText: FormStrings.measurementPrivacyUrl,
                  suffixIcon: UnitMeasurementHelpButton(
                    UnitMeasurementHelp.privacy,
                    label: FormStrings.measurementPrivacyUrl,
                  ),
                  helperText: FormStrings.measurementPrivacyUrlHelp,
                  helperMaxLines: 6,
                  border: const OutlineInputBorder(),
                ),
                validator: (value) {
                  final text = value?.trim() ?? '';
                  if (text.isEmpty) {
                    return _privacyUrlRequired
                        ? FormStrings.measurementPrivacyUrlRequired
                        : null;
                  }
                  return text.length <= 2048 &&
                          RegExp(
                            r'^https://[A-Za-z0-9]([A-Za-z0-9-]*[A-Za-z0-9])?(\.[A-Za-z0-9]([A-Za-z0-9-]*[A-Za-z0-9])?)*(:([0-9]{1,4}|[1-5][0-9]{4}|6[0-4][0-9]{3}|65[0-4][0-9]{2}|655[0-2][0-9]|6553[0-5]))?([/?#][^\s\\]*)?$',
                          ).hasMatch(text)
                      ? null
                      : FormStrings.measurementPrivacyUrlInvalid;
                },
              ),
            ];
            return wide
                ? Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      for (final (index, field) in fields.indexed) ...[
                        if (index != 0) const SizedBox(width: 24),
                        Expanded(child: field),
                      ],
                    ],
                  )
                : Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      for (final (index, field) in fields.indexed) ...[
                        if (index != 0) const SizedBox(height: 12),
                        field,
                      ],
                    ],
                  );
          },
        ),
        if (!enabled) ...[
          const SizedBox(height: 8),
          Text(
            FormStrings.measurementUnitDisabled,
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ],
        if (canEdit &&
            _privacyUrlRequired &&
            privacyUrlController.text.trim().isEmpty) ...[
          const SizedBox(height: 8),
          Text(
            FormStrings.measurementNoPrivacyPolicy,
            style: TextStyle(color: theme.colorScheme.error),
          ),
        ],
        if (enabled && approval?.approved != true && loadingApproval) ...[
          const SizedBox(height: 8),
          Text(CommonStrings.loading),
        ] else if (enabled &&
            approval?.approved != true &&
            (approvalLoadFailed ||
                approval?.requestState ==
                    MeasurementRequestState.unavailable)) ...[
          const SizedBox(height: 8),
          Align(
            alignment: Alignment.centerLeft,
            child: OutlinedButton(
              style: OutlinedButton.styleFrom(minimumSize: const Size(48, 48)),
              onPressed: onRetryApproval,
              child: Text(CommonStrings.retry),
            ),
          ),
        ] else if (enabled && statusKnown && !approval!.approved) ...[
          const SizedBox(height: 8),
          Semantics(
            liveRegion: true,
            child: Text(
              approval!.requestState == MeasurementRequestState.requested
                  ? approval!.requestedAt == null
                        ? FormStrings.measurementPlatformPending
                        : FormStrings.measurementApprovalRequested(
                            DateFormat.yMd(
                              Localizations.localeOf(context).toString(),
                            ).format(approval!.requestedAt!.toLocal()),
                          )
                  : unsaved
                  ? FormStrings.measurementWebsitesSaveFirst
                  : approval!.requestState ==
                            MeasurementRequestState.retryAvailable &&
                        approval!.canRequest
                  ? FormStrings.measurementApprovalRetry
                  : FormStrings.measurementFirstApprovalHelp,
            ),
          ),
          if (canEdit &&
              !unsaved &&
              onRequestApproval != null &&
              approval!.canRequest &&
              approval!.requestState != MeasurementRequestState.requested &&
              validateWebsites(websitesController?.text) == null) ...[
            const SizedBox(height: 8),
            Align(
              alignment: Alignment.centerLeft,
              child: OutlinedButton(
                style: OutlinedButton.styleFrom(
                  minimumSize: const Size(48, 48),
                ),
                onPressed: requestingApproval ? null : onRequestApproval,
                child: Text(FormStrings.measurementApprovalRequest),
              ),
            ),
          ],
        ],
        if (websitesController != null) ...[
          gap,
          UnitMeasurementSectionTitle(
            FormStrings.measurementWebsites,
            UnitMeasurementHelp.websites,
            style: theme.textTheme.titleMedium,
          ),
          const SizedBox(height: 12),
          for (final site in sites)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 4),
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(site.replaceFirst('https://', '')),
                        if (!savedWebsites.contains(site))
                          Wrap(
                            spacing: 8,
                            crossAxisAlignment: WrapCrossAlignment.center,
                            children: [
                              Chip(
                                label: Text(
                                  FormStrings.measurementWebsiteDraft,
                                ),
                              ),
                              Text(
                                FormStrings.measurementUnsavedHelp,
                                style: theme.textTheme.bodySmall,
                              ),
                            ],
                          ),
                      ],
                    ),
                  ),
                  if (canEdit)
                    IconButton(
                      tooltip: FormStrings.measurementRemoveWebsite(site),
                      constraints: const BoxConstraints(
                        minWidth: 48,
                        minHeight: 48,
                      ),
                      icon: const Icon(Icons.close),
                      onPressed: () {
                        websitesController!.text = sites
                            .where((value) => value != site)
                            .join('\n');
                      },
                    ),
                ],
              ),
            ),
          if (sites.isNotEmpty) const SizedBox(height: 8),
          _WebsiteAdder(controller: websitesController!, canEdit: canEdit),
        ],
        gap,
        Row(
          children: [
            Expanded(
              child: SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: Text(FormStrings.measurementConsentBridge),
                subtitle: Text(FormStrings.measurementBridgeHelp),
                value: consentBridge,
                onChanged: canEdit && onConsentBridgeChanged != null
                    ? (value) async {
                        if (!value) {
                          onConsentBridgeChanged!(false);
                          return;
                        }
                        final confirmed = await _terms(context, confirm: true);
                        if (context.mounted && confirmed == true) {
                          onConsentBridgeChanged!(true);
                        }
                      }
                    : null,
              ),
            ),
            UnitMeasurementHelpButton(
              UnitMeasurementHelp.transfer,
              label: FormStrings.measurementConsentBridge,
            ),
          ],
        ),
        if (consentBridge)
          Wrap(
            crossAxisAlignment: WrapCrossAlignment.center,
            spacing: 8,
            children: [
              Text(
                FormStrings.measurementTermsAccepted,
                style: theme.textTheme.bodySmall,
              ),
              TextButton(
                style: TextButton.styleFrom(minimumSize: const Size(48, 48)),
                onPressed: () => _terms(context),
                child: Text(FormStrings.measurementShowTerms),
              ),
            ],
          ),
        if (canEdit && websiteConsentBuilder != null) websiteConsentBuilder!(),
        gap,
        ExpansionTile(
          tilePadding: EdgeInsets.zero,
          maintainState: true,
          key: const PageStorageKey("measurement-section-banner"),
          title: UnitMeasurementSectionTitle(
            FormStrings.measurementOwnBanner,
            UnitMeasurementHelp.banner,
          ),
          subtitle: Text(FormStrings.measurementBannerFallback),
          shape: sectionShape,
          collapsedShape: sectionShape,
          expandedCrossAxisAlignment: CrossAxisAlignment.stretch,
          childrenPadding: const EdgeInsets.only(top: 8, bottom: 16),
          children: [
            DropdownButtonFormField<String>(
              isExpanded: true,
              key: ValueKey(consentLayout),
              initialValue: consentLayout,
              decoration: InputDecoration(
                labelText: FormStrings.measurementConsentLayout,
                border: const OutlineInputBorder(),
              ),
              items: [
                DropdownMenuItem(
                  value: 'bar',
                  child: Text(FormStrings.measurementConsentLayoutBar),
                ),
                DropdownMenuItem(
                  value: 'modal',
                  child: Text(FormStrings.measurementConsentLayoutModal),
                ),
              ],
              onChanged: canEdit
                  ? (value) {
                      if (value != null) onConsentLayoutChanged(value);
                    }
                  : null,
            ),
            const SizedBox(height: 16),
            TextFormField(
              key: const PageStorageKey("measurement-consentTitleController"),
              controller: consentTitleController,
              enabled: canEdit,
              maxLength: 80,
              minLines: 1,
              maxLines: null,
              textInputAction: TextInputAction.done,
              inputFormatters: [
                FilteringTextInputFormatter.singleLineFormatter,
              ],
              decoration: InputDecoration(
                labelText: FormStrings.measurementConsentCustomTitle,
                helper: Text(
                  FormStrings.measurementConsentCustomTitleHelp,
                  style: hintStyle,
                ),
                border: const OutlineInputBorder(),
              ),
            ),
            _restore(
              consentTitleController,
              FormStrings.measurementConsentDefaultTitle,
            ),
            const SizedBox(height: 16),
            TextFormField(
              key: const PageStorageKey("measurement-consentTextController"),
              controller: consentTextController,
              enabled: canEdit,
              minLines: 3,
              maxLines: 8,
              maxLength: 500,
              decoration: InputDecoration(
                labelText: FormStrings.measurementConsentCustomText,
                helper: Text(
                  FormStrings.measurementConsentCustomTextHelp,
                  style: hintStyle,
                ),
                border: const OutlineInputBorder(),
              ),
            ),
            _restore(
              consentTextController,
              FormStrings.measurementConsentDefaultText,
            ),
          ],
        ),
        const SizedBox(height: 8),
        ExpansionTile(
          tilePadding: EdgeInsets.zero,
          shape: sectionShape,
          collapsedShape: sectionShape,
          expandedCrossAxisAlignment: CrossAxisAlignment.stretch,
          childrenPadding: const EdgeInsets.only(top: 8, bottom: 16),
          // Collapsed scripts must stay in the Form so the validator runs.
          maintainState: true,
          key: const PageStorageKey("measurement-section-scripts"),
          title: UnitMeasurementSectionTitle(
            FormStrings.measurementAdvanced,
            UnitMeasurementHelp.scripts,
          ),
          children: [
            TextFormField(
              key: const PageStorageKey("measurement-scriptsController"),
              controller: scriptsController,
              enabled: canEdit,
              minLines: 5,
              maxLines: 10,
              maxLength: formMeasurementScriptLimit,
              decoration: InputDecoration(
                labelText: FormStrings.measurementScripts,
                floatingLabelBehavior: FloatingLabelBehavior.always,
                alignLabelWithHint: true,
                helper: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  spacing: 8,
                  children: [
                    for (final paragraph
                        in FormStrings.measurementScriptsHelp.split('\n\n'))
                      Text(paragraph, style: hintStyle),
                  ],
                ),
                border: const OutlineInputBorder(),
              ),
              validator: (value) =>
                  (value?.runes.length ?? 0) <= formMeasurementScriptLimit
                  ? null
                  : FormStrings.measurementScriptsTooLong,
            ),
          ],
        ),
        const SizedBox(height: 8),
        ExpansionTile(
          tilePadding: EdgeInsets.zero,
          shape: sectionShape,
          collapsedShape: sectionShape,
          expandedCrossAxisAlignment: CrossAxisAlignment.stretch,
          childrenPadding: const EdgeInsets.only(top: 8, bottom: 16),
          key: const PageStorageKey("measurement-section-help"),
          title: UnitMeasurementSectionTitle(
            FormStrings.measurementHowItWorks,
            UnitMeasurementHelp.overview,
          ),
          children: [
            Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              spacing: 12,
              children: [
                for (final paragraph
                    in FormStrings.measurementActivationHelp.split('\n\n'))
                  Text(
                    paragraph,
                    style: theme.textTheme.bodyMedium?.copyWith(height: 1.45),
                  ),
              ],
            ),
          ],
        ),
      ],
    );
  }

  Future<bool?> _terms(BuildContext context, {bool confirm = false}) =>
      showDialog<bool>(
        context: context,
        builder: (context) => AppAlertDialog(
          insetPadding: MediaQuery.sizeOf(context).width < 600
              ? const EdgeInsets.all(16)
              : null,
          title: Text(FormStrings.measurementConsentBridge),
          onClose: () => Navigator.of(context).pop(),
          content: SingleChildScrollView(
            child: Text(FormStrings.measurementConsentBridgeConfirmation),
          ),
          actions: [
            TextButton(
              style: TextButton.styleFrom(minimumSize: const Size(48, 48)),
              onPressed: () => Navigator.of(context).pop(),
              child: Text(confirm ? CommonStrings.cancel : CommonStrings.close),
            ),
            if (confirm)
              FilledButton(
                style: FilledButton.styleFrom(minimumSize: const Size(48, 48)),
                onPressed: () => Navigator.of(context).pop(true),
                child: Text(CommonStrings.confirm),
              ),
          ],
        ),
      );

  /// Stored overrides can be cleared even when identical to the localized default.
  Widget _restore(TextEditingController controller, String fallback) =>
      canEdit &&
          (controller.text.trim() != fallback.trim() ||
              (controller == consentTitleController
                  ? hasStoredTitle
                  : hasStoredText))
      ? Padding(
          padding: const EdgeInsets.only(top: 8),
          child: Align(
            alignment: Alignment.centerLeft,
            child: TextButton.icon(
              style: TextButton.styleFrom(
                minimumSize: const Size(48, 48),
                padding: EdgeInsets.zero,
              ),
              icon: const Icon(Icons.restore, size: 18),
              label: Text(FormStrings.measurementConsentRestoreDefault),
              onPressed: () {
                onRestore?.call(controller);
                controller.text = fallback;
              },
            ),
          ),
        )
      : const SizedBox.shrink();
}

class _WebsiteAdder extends StatefulWidget {
  final TextEditingController controller;
  final bool canEdit;
  const _WebsiteAdder({required this.controller, required this.canEdit});
  @override
  State<_WebsiteAdder> createState() => _WebsiteAdderState();
}

class _WebsiteAdderState extends State<_WebsiteAdder> {
  final _input = TextEditingController();
  final _inputField = GlobalKey<FormFieldState<String>>();
  String? _error;
  @override
  void dispose() {
    _input.dispose();
    super.dispose();
  }

  void _add() {
    final value = _input.text.trim();
    final sites = UnitMeasurementSettings.parseWebsites(widget.controller.text);
    final error = value.isEmpty
        ? FormStrings.measurementWebsitesInvalid
        : UnitMeasurementSettings.validateWebsites(
            [...sites, value].join('\n'),
          );
    setState(() => _error = error);
    if (error != null) return;
    widget.controller.text = {...sites, value}.join('\n');
    _input.clear();
    _inputField.currentState?.validate();
  }

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      // Keep the canonical controller in the form's validation lifecycle.
      FormField<String>(
        validator: (_) =>
            UnitMeasurementSettings.validateWebsites(widget.controller.text),
        builder: (state) => state.hasError
            ? Text(
                state.errorText!,
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              )
            : const SizedBox.shrink(),
      ),
      LayoutBuilder(
        builder: (context, constraints) {
          final field = TextFormField(
            key: _inputField,
            controller: _input,
            validator: (value) {
              final address = value?.trim() ?? '';
              if (address.isEmpty || !widget.canEdit) return null;
              return UnitMeasurementSettings.validateWebsites(
                    '${widget.controller.text}\n$address',
                  ) ??
                  FormStrings.measurementFinishAddingWebsite;
            },
            onChanged: (_) {
              if (_error != null) setState(() => _error = null);
              if (_inputField.currentState?.hasError == true) {
                _inputField.currentState!.validate();
              }
            },
            enabled: widget.canEdit,
            keyboardType: TextInputType.url,
            textInputAction: TextInputAction.done,
            maxLines: constraints.maxWidth >= 800 ? 1 : null,
            minLines: 1,
            onFieldSubmitted: widget.canEdit ? (_) => _add() : null,
            decoration: InputDecoration(
              labelText: FormStrings.measurementAddWebsite,
              hintText: 'https://',
              errorText: _error,
              errorMaxLines: 4,
              helperText: FormStrings.measurementWebsitesHelp,
              helperMaxLines: 8,
              border: const OutlineInputBorder(),
            ),
          );
          final button = Align(
            alignment: Alignment.centerLeft,
            child: OutlinedButton.icon(
              style: OutlinedButton.styleFrom(minimumSize: const Size(48, 48)),
              onPressed: widget.canEdit ? _add : null,
              icon: const Icon(Icons.add),
              label: Text(CommonStrings.add),
            ),
          );
          return constraints.maxWidth >= 800
              ? Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(child: field),
                    const SizedBox(width: 16),
                    Padding(
                      padding: const EdgeInsets.only(top: 8),
                      child: button,
                    ),
                  ],
                )
              : Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  spacing: 8,
                  children: [field, button],
                );
        },
      ),
    ],
  );
}
