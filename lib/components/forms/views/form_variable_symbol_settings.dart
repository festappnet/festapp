import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:festapp_core/forms.dart';

import '../form_strings.dart';

/// Canonical form metadata controls, shared by the form editor and setup.
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
    final type = value[FormDefinition.metaType] as String? ?? 'random';
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        DropdownButtonFormField<String>(
          initialValue: type,
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
              ? (v) => onChanged({...value, FormDefinition.metaType: v})
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
            keyboardType: TextInputType.number,
            maxLength: 10,
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
