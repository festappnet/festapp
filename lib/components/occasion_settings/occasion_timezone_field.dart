import 'package:material_ui/material_ui.dart';

import 'occasion_settings_strings.dart';

class OccasionTimezoneField extends StatelessWidget {
  final String? selectedTimezone;
  final List<String> allTimezones;
  final bool isEditingEnabled;
  final ValueChanged<String> onTimezoneSelected;

  const OccasionTimezoneField({
    super.key,
    required this.selectedTimezone,
    required this.allTimezones,
    required this.isEditingEnabled,
    required this.onTimezoneSelected,
  });

  @override
  Widget build(BuildContext context) {
    return Autocomplete<String>(
      initialValue:
          selectedTimezone != null && allTimezones.contains(selectedTimezone)
          ? TextEditingValue(text: selectedTimezone!)
          : null,
      optionsBuilder: (TextEditingValue textEditingValue) {
        if (!isEditingEnabled) {
          return const Iterable<String>.empty();
        }
        if (textEditingValue.text.isEmpty) {
          return allTimezones.take(50);
        }
        return allTimezones.where((String option) {
          return option.toLowerCase().contains(
            textEditingValue.text.toLowerCase(),
          );
        });
      },
      onSelected: onTimezoneSelected,
      fieldViewBuilder:
          (
            BuildContext context,
            TextEditingController fieldTextEditingController,
            FocusNode fieldFocusNode,
            VoidCallback onFieldSubmitted,
          ) {
            return TextFormField(
              controller: fieldTextEditingController,
              focusNode: fieldFocusNode,
              enabled: isEditingEnabled,
              decoration: InputDecoration(
                labelText: OccasionSettingsStrings.timezone,
                border: const OutlineInputBorder(),
                suffixIcon:
                    fieldTextEditingController.text.isNotEmpty &&
                        isEditingEnabled
                    ? IconButton(
                        icon: const Icon(Icons.clear),
                        onPressed: () {
                          fieldTextEditingController.clear();
                          onTimezoneSelected('');
                        },
                      )
                    : null,
              ),
              validator: (value) {
                if (value == null || value.isEmpty) {
                  return OccasionSettingsStrings.timezoneIsRequired;
                }
                if (!allTimezones.contains(value)) {
                  if (selectedTimezone != value) {
                    return OccasionSettingsStrings.invalidTimezone;
                  }
                }
                return null;
              },
              onFieldSubmitted: (_) => onFieldSubmitted(),
            );
          },
      optionsViewBuilder:
          (
            BuildContext context,
            AutocompleteOnSelected<String> onSelected,
            Iterable<String> options,
          ) {
            return Align(
              alignment: Alignment.topLeft,
              child: Material(
                elevation: 4.0,
                child: ConstrainedBox(
                  constraints: BoxConstraints(
                    maxHeight: 300,
                    maxWidth: MediaQuery.of(context).size.width - 40 > 0
                        ? MediaQuery.of(context).size.width - 40
                        : 300,
                  ),
                  child: ListView.builder(
                    padding: EdgeInsets.zero,
                    itemCount: options.length,
                    shrinkWrap: true,
                    itemBuilder: (BuildContext context, int index) {
                      final String option = options.elementAt(index);
                      return InkWell(
                        onTap: () {
                          onSelected(option);
                        },
                        child: Padding(
                          padding: const EdgeInsets.all(16.0),
                          child: Text(option),
                        ),
                      );
                    },
                  ),
                ),
              ),
            );
          },
    );
  }
}
