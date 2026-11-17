import 'package:flutter/foundation.dart' show setEquals;

import '../unit_settings_fields.dart';

import 'package:fstapp/widgets/app_dialog.dart';

import 'package:festapp_core/forms.dart';
import 'package:fstapp/components/forms/form_strings.dart';
import 'package:fstapp/components/_shared/common_strings.dart';
import 'package:material_ui/material_ui.dart';
import 'package:intl/intl.dart';

import '../unit_measurement_approval.dart';

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
    String websiteStatus(String site) {
      if (!statusKnown) return FormStrings.measurementWebsiteUnknown;
      if (!approval!.savedOrigins.contains(site)) {
        return FormStrings.measurementWebsiteDraft;
      }
      if (approval!.approvedOrigins.contains(site)) {
        return FormStrings.measurementWebsiteApproved;
      }
      if (approval!.requestState == MeasurementRequestState.requested &&
          approval!.requestedOrigins.contains(site)) {
        return FormStrings.measurementWebsitePending;
      }
      return FormStrings.measurementWebsiteUnrequested;
    }

    final running =
        enabled &&
        statusKnown &&
        !unsaved &&
        sites.isNotEmpty &&
        approval!.approved &&
        approval!.organizationAllowed &&
        approval!.runtimeSupported &&
        sites.every(approval!.approvedOrigins.contains) &&
        privacyUrlController.text.trim().isNotEmpty &&
        (gtmController.text.trim().isNotEmpty ||
            scriptsController.text.trim().isNotEmpty);
    const gap = SizedBox(height: 24);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            if (running)
              Chip(
                avatar: const Icon(Icons.check_circle_outline, size: 18),
                label: Text(
                  FormStrings.measurementRunningCount(
                    sites.length,
                    Localizations.localeOf(context).toLanguageTag(),
                  ),
                ),
              )
            else ...[
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
              if (sites.any(
                (site) =>
                    websiteStatus(site) ==
                    FormStrings.measurementWebsitePending,
              ))
                Chip(
                  avatar: const Icon(Icons.schedule, size: 18),
                  label: Text(
                    FormStrings.measurementPendingCount(
                      sites
                          .where(
                            (site) =>
                                websiteStatus(site) ==
                                FormStrings.measurementWebsitePending,
                          )
                          .length,
                      Localizations.localeOf(context).toLanguageTag(),
                    ),
                  ),
                ),
            ],
          ],
        ),
        gap,
        Text(
          '1  ${FormStrings.measurementBasics}',
          style: theme.textTheme.titleMedium,
        ),
        const SizedBox(height: 8),
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          title: Text(FormStrings.measurementUnitEnabled),
          subtitle: Text(FormStrings.measurementUnitHelp),
          value: enabled,
          onChanged: canEdit ? onEnabledChanged : null,
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
        gap,
        LayoutBuilder(
          builder: (context, constraints) {
            final fields = <Widget>[
              TextFormField(
                key: const PageStorageKey("measurement-gtmController"),
                controller: gtmController,
                enabled: canEdit,
                maxLength: 36,
                decoration: InputDecoration(
                  labelText: FormStrings.gtmContainer,
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
                keyboardType: TextInputType.url,
                decoration: InputDecoration(
                  labelText: FormStrings.measurementPrivacyUrl,
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
            return constraints.maxWidth >= 800
                ? Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(child: fields[0]),
                      const SizedBox(width: 24),
                      Expanded(child: fields[1]),
                    ],
                  )
                : Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [fields[0], gap, fields[1]],
                  );
          },
        ),
        if (websitesController != null) ...[
          gap,
          Text(
            '2  ${FormStrings.measurementWebsites}',
            style: theme.textTheme.titleMedium,
          ),
          const SizedBox(height: 12),
          for (final site in sites)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 6),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: LayoutBuilder(
                      builder: (context, constraints) => Wrap(
                        crossAxisAlignment: WrapCrossAlignment.center,
                        spacing: 8,
                        runSpacing: 4,
                        children: [
                          SizedBox(
                            width: constraints.maxWidth < 600
                                ? constraints.maxWidth
                                : null,
                            child: Text(site.replaceFirst('https://', '')),
                          ),
                          Chip(
                            avatar: Icon(
                              approval?.approvedOrigins.contains(site) == true
                                  ? Icons.check_circle_outline
                                  : Icons.schedule,
                              size: 18,
                            ),
                            label: Text(
                              websiteStatus(site) ==
                                          FormStrings
                                              .measurementWebsitePending &&
                                      approval?.requestedAt != null
                                  ? '${websiteStatus(site)} · ${DateFormat.Md(Localizations.localeOf(context).toString()).format(approval!.requestedAt!.toLocal())}'
                                  : websiteStatus(site),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  if (canEdit)
                    IconButton(
                      tooltip: FormStrings.measurementRemoveWebsite,
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
          _WebsiteAdder(controller: websitesController!, canEdit: canEdit),
        ],
        if (enabled && loadingApproval) ...[
          const SizedBox(height: 8),
          Text(CommonStrings.loading),
        ] else if (enabled &&
            (approvalLoadFailed ||
                approval?.requestState ==
                    MeasurementRequestState.unavailable)) ...[
          const SizedBox(height: 8),
          Align(
            alignment: Alignment.centerLeft,
            child: OutlinedButton(
              onPressed: onRetryApproval,
              child: Text(CommonStrings.retry),
            ),
          ),
        ] else if (enabled && statusKnown) ...[
          const SizedBox(height: 8),
          if (!approval!.approved)
            Text(FormStrings.measurementApprovalRequired),
          if (unsaved)
            Text(FormStrings.measurementWebsitesSaveFirst)
          else if (approval!.requestState ==
                  MeasurementRequestState.retryAvailable &&
              approval!.canRequest)
            Text(FormStrings.measurementApprovalRetry)
          else if (approval!.canRequest && approval!.approved)
            Text(FormStrings.measurementWebsitesReady),
          if (canEdit &&
              !unsaved &&
              approval!.canRequest &&
              validateWebsites(websitesController?.text) == null) ...[
            const SizedBox(height: 8),
            Align(
              alignment: Alignment.centerLeft,
              child: OutlinedButton(
                onPressed:
                    canEdit &&
                        !requestingApproval &&
                        !unsaved &&
                        approval!.canRequest &&
                        validateWebsites(websitesController?.text) == null
                    ? onRequestApproval
                    : null,
                child: Text(FormStrings.measurementApprovalRequest),
              ),
            ),
          ],
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
        gap,
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          title: Text('3  ${FormStrings.measurementConsentBridge}'),
          subtitle: Text(FormStrings.measurementBridgeHelp),
          value: consentBridge,
          onChanged: canEdit && onConsentBridgeChanged != null
              ? (value) async {
                  if (!value) {
                    onConsentBridgeChanged!(false);
                    return;
                  }
                  final confirmed = await _terms(context, confirm: true);
                  if (confirmed == true) onConsentBridgeChanged!(true);
                }
              : null,
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
          title: Text(FormStrings.measurementOwnBanner),
          subtitle: Text(FormStrings.measurementBannerFallback),
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
            gap,
            TextFormField(
              key: const PageStorageKey("measurement-consentTitleController"),
              controller: consentTitleController,
              enabled: canEdit,
              maxLength: 80,
              decoration: InputDecoration(
                labelText: FormStrings.measurementConsentCustomTitle,
                helperText: FormStrings.measurementConsentCustomTitleHelp,
                helperMaxLines: 3,
                border: const OutlineInputBorder(),
              ),
            ),
            _restore(
              consentTitleController,
              FormStrings.measurementConsentDefaultTitle,
            ),
            gap,
            TextFormField(
              key: const PageStorageKey("measurement-consentTextController"),
              controller: consentTextController,
              enabled: canEdit,
              minLines: 3,
              maxLines: 8,
              maxLength: 500,
              decoration: InputDecoration(
                labelText: FormStrings.measurementConsentCustomText,
                helperText: FormStrings.measurementConsentCustomTextHelp,
                helperMaxLines: 3,
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
          childrenPadding: const EdgeInsets.only(top: 8),
          // Collapsed scripts must stay in the Form so the validator runs.
          maintainState: true,
          key: const PageStorageKey("measurement-section-scripts"),
          title: Text(FormStrings.measurementAdvanced),
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
                helperText: FormStrings.measurementScriptsHelp,
                helperMaxLines: 8,
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
          key: const PageStorageKey("measurement-section-help"),
          title: Text(FormStrings.measurementHowItWorks),
          children: [
            Text(
              FormStrings.measurementActivationHelp,
              style: theme.textTheme.bodySmall,
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
          title: Text(FormStrings.measurementConsentBridge),
          onClose: () => Navigator.of(context).pop(),
          content: SingleChildScrollView(
            child: Text(FormStrings.measurementConsentBridgeConfirmation),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: Text(CommonStrings.cancel),
            ),
            if (confirm)
              FilledButton(
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
      ? Align(
          alignment: Alignment.centerRight,
          child: TextButton.icon(
            icon: const Icon(Icons.restore, size: 18),
            label: Text(FormStrings.measurementConsentRestoreDefault),
            onPressed: () {
              onRestore?.call(controller);
              controller.text = fallback;
            },
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
          final field = TextField(
            key: const PageStorageKey("measurement-add-website"),
            controller: _input,
            enabled: widget.canEdit,
            onSubmitted: widget.canEdit ? (_) => _add() : null,
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
                  children: [field, button],
                );
        },
      ),
    ],
  );
}
