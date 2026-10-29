import 'package:material_ui/material_ui.dart';
import 'package:flutter/services.dart';
import 'package:festapp_core/forms.dart';

import '../form_strings.dart';

/// Advanced form authoring and explicit repair of legacy setup policies.
class FormVariableSymbolSettings extends StatelessWidget {
  final Map<String, dynamic> value;
  final ValueChanged<Map<String, dynamic>> onChanged;
  final bool enabled;
  const FormVariableSymbolSettings({
    super.key,
    required this.value,
    required this.onChanged,
    this.enabled = true,
  });
  @override
  Widget build(BuildContext context) {
    final type = value[FormDefinition.metaType] ?? 'random';
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        DropdownButtonFormField<String>(
          initialValue: const ['random', 'sequence'].contains(type)
              ? type
              : null,
          autovalidateMode: AutovalidateMode.onUserInteraction,
          validator: (v) =>
              v == null ? FormStrings.invalidVariableSymbolPolicy : null,
          isExpanded: true,
          decoration: InputDecoration(
            labelText: FormStrings.labelVariableSymbol,
            border: const OutlineInputBorder(),
          ),
          items: [
            DropdownMenuItem(
              value: 'random',
              child: Text(FormStrings.vsTypeRandom),
            ),
            DropdownMenuItem(
              value: 'sequence',
              child: Text(FormStrings.vsTypeSequence),
            ),
          ],
          onChanged: enabled
              ? (v) {
                  final next = {...value, FormDefinition.metaType: v};
                  if (v == 'random')
                    next.remove(FormDefinition.metaStartingNumber);
                  onChanged(next);
                }
              : null,
        ),
        if (type == 'sequence') ...[
          const SizedBox(height: 16),
          TextFormField(
            initialValue: '${value[FormDefinition.metaStartingNumber] ?? ''}',
            enabled: enabled,
            decoration: InputDecoration(
              labelText: FormStrings.labelStartingNumber,
              helperText: FormStrings.helperStartingNumber,
              helperMaxLines: 5,
              border: const OutlineInputBorder(),
              counterText: '',
            ),
            autovalidateMode: AutovalidateMode.onUserInteraction,
            validator: (text) =>
                formVariableSymbolPolicyValid({
                  'type': 'sequence',
                  'starting_number': int.tryParse(text ?? ''),
                })
                ? null
                : FormStrings.invalidVariableSymbolPolicy,
            keyboardType: TextInputType.number,
            maxLength: 10,
            maxLengthEnforcement: MaxLengthEnforcement.none,
            inputFormatters: [FilteringTextInputFormatter.digitsOnly],
            onChanged: (v) => onChanged({
              ...value,
              FormDefinition.metaStartingNumber: int.tryParse(v),
            }),
          ),
        ],
      ],
    );
  }
}
