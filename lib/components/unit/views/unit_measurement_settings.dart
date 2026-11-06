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
  final ValueChanged<bool> onEnabledChanged;

  const UnitMeasurementSettings({
    super.key,
    required this.enabled,
    required this.canEdit,
    required this.gtmController,
    required this.scriptsController,
    required this.onEnabledChanged,
  });

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text(
        FormStrings.measurementTitle,
        style: Theme.of(context).textTheme.titleLarge,
      ),
      const SizedBox(height: 8),
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
