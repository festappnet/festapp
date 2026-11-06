import 'package:festapp_core/forms.dart';
import 'package:fstapp/components/forms/form_strings.dart';
import 'package:material_ui/material_ui.dart';

/// Destination configuration is independent of permission to run measurement.
/// The owning screen saves these fields through the canonical Unit aggregate.
class UnitMeasurementSettings extends StatelessWidget {
  final bool enabled;
  final bool canEdit;
  final TextEditingController gtmController;
  final TextEditingController scriptsController;
  final TextEditingController privacyUrlController;
  final ExpansibleController? controller;
  final ValueChanged<bool> onEnabledChanged;

  const UnitMeasurementSettings({
    super.key,
    required this.enabled,
    required this.canEdit,
    required this.gtmController,
    required this.scriptsController,
    required this.privacyUrlController,
    required this.onEnabledChanged,
    this.controller,
  });

  bool get _privacyUrlRequired =>
      enabled &&
      (gtmController.text.trim().isNotEmpty ||
          scriptsController.text.trim().isNotEmpty);

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: Listenable.merge([
      gtmController,
      scriptsController,
      privacyUrlController,
    ]),
    builder: (context, _) => _tile(context),
  );

  Widget _tile(BuildContext context) => ExpansionTile(
    controller: controller,
    initiallyExpanded: false,
    // Collapsed fields must stay in the Form so their validators still run.
    maintainState: true,
    tilePadding: EdgeInsets.zero,
    title: Text(
      FormStrings.measurementTitle,
      style: Theme.of(context).textTheme.titleLarge,
    ),
    subtitle: canEdit && _privacyUrlRequired &&
            privacyUrlController.text.trim().isEmpty
        ? Text(
            FormStrings.measurementNoPrivacyPolicy,
            style: TextStyle(color: Theme.of(context).colorScheme.error),
          )
        : null,
    expandedCrossAxisAlignment: CrossAxisAlignment.start,
    children: [
      SwitchListTile(
        contentPadding: EdgeInsets.zero,
        title: Text(FormStrings.measurementUnitEnabled),
        subtitle: Text(FormStrings.measurementUnitHelp),
        value: enabled,
        onChanged: canEdit ? onEnabledChanged : null,
      ),
      if (!enabled) Text(FormStrings.measurementUnitDisabled),
      const SizedBox(height: 16),
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
      const SizedBox(height: 16),
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
                ? FormStrings.measurementPrivacyUrlRequired : null;
          }
          return text.length <= 2048 &&
                  RegExp(
                    r'^https://[A-Za-z0-9]([A-Za-z0-9-]*[A-Za-z0-9])?(\.[A-Za-z0-9]([A-Za-z0-9-]*[A-Za-z0-9])?)*(:([0-9]{1,4}|[1-5][0-9]{4}|6[0-4][0-9]{3}|65[0-4][0-9]{2}|655[0-2][0-9]|6553[0-5]))?([/?#][^\s\\]*)?$',
                  ).hasMatch(text)
              ? null
              : FormStrings.measurementPrivacyUrlInvalid;
        },
      ),
      const SizedBox(height: 16),
      ExpansionTile(
        tilePadding: EdgeInsets.zero,
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
      Text(FormStrings.measurementActivationHelp),
    ],
  );
}
