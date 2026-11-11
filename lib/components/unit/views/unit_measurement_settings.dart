import 'package:flutter/foundation.dart' show setEquals;

import '../unit_settings_fields.dart';

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

    const gap = SizedBox(height: 24);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(FormStrings.measurementTitle, style: theme.textTheme.titleMedium),
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
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          title: Text(FormStrings.measurementConsentBridge),
          subtitle: Text(FormStrings.measurementConsentBridgeConfirmation),
          value: consentBridge,
          onChanged: canEdit ? onConsentBridgeChanged : null,
        ),
        if (websitesController != null) ...[
          gap,
          TextFormField(
            controller: websitesController,
            enabled: canEdit,
            minLines: 2,
            maxLines: 10,
            decoration: InputDecoration(
              labelText: FormStrings.measurementWebsites,
              helperText: FormStrings.measurementWebsitesHelp,
              helperMaxLines: 12,
              errorMaxLines: 4,
              border: const OutlineInputBorder(),
            ),
            autovalidateMode: AutovalidateMode.onUserInteraction,
            validator: validateWebsites,
          ),
          for (final site in sites) Text('$site: ${websiteStatus(site)}'),
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
            Text(FormStrings.measurementWebsitesReady)
          else if (approval!.requestState ==
                  MeasurementRequestState.requested &&
              approval!.requestedAt != null)
            Text(
              FormStrings.measurementApprovalRequested(
                DateFormat.yMd(Localizations.localeOf(context).toString())
                    .format(approval!.requestedAt!.toLocal()),
              ),
            ),
          if (approval!.canRequest ||
              approval!.requestState == MeasurementRequestState.requested ||
              unsaved) ...[
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
        TextFormField(
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
        gap,
        TextFormField(
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
        gap,
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
        const SizedBox(height: 8),
        ExpansionTile(
          tilePadding: EdgeInsets.zero,
          childrenPadding: const EdgeInsets.only(top: 8),
          // Collapsed scripts must stay in the Form so the validator runs.
          maintainState: true,
          title: Text(FormStrings.measurementAdvanced),
          children: [
            TextFormField(
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
        Text(
          FormStrings.measurementActivationHelp,
          style: theme.textTheme.bodySmall?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
      ],
    );
  }

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
