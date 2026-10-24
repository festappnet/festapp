import 'package:fstapp/components/forms/email_validation.dart';
import 'package:flutter/material.dart';
import 'package:fstapp/app_config.dart';
import 'package:fstapp/database_tables/tb.dart';
import 'package:fstapp/data_services/rights_service.dart';
import 'package:fstapp/components/forms/views/form_public_link.dart';
import 'package:fstapp/components/forms/form_strings.dart';

import 'occasion_settings_strings.dart';

class OccasionAdvancedSettings extends StatelessWidget {
  final TextEditingController linkController;
  final String? savedLink;
  final TextEditingController replyToEmailController;
  final String? selectedTimezone;
  final List<String> allTimezones;
  final bool isEditingEnabled;
  final bool initiallyExpanded;
  final ValueChanged<bool> onExpansionChanged;
  final ValueChanged<String> onTimezoneSelected;
  final ValueChanged<String> onLinkChanged;
  final ValueChanged<String?> onLinkSaved;
  const OccasionAdvancedSettings({
    super.key,
    required this.linkController,
    this.savedLink,
    required this.replyToEmailController,
    required this.selectedTimezone,
    required this.allTimezones,
    required this.isEditingEnabled,
    required this.initiallyExpanded,
    required this.onExpansionChanged,
    required this.onTimezoneSelected,
    required this.onLinkChanged,
    required this.onLinkSaved,
  });

  @override
  Widget build(BuildContext context) {
    return ExpansionTile(
      title: Text(
        OccasionSettingsStrings.advancedSettings,
        style: Theme.of(context)
            .textTheme
            .titleMedium
            ?.copyWith(fontWeight: FontWeight.bold),
      ),
      initiallyExpanded: initiallyExpanded,
      onExpansionChanged: onExpansionChanged,
      children: <Widget>[
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (AppConfig.isAppSupported) ...[
                TextFormField(
                    controller: linkController,
                    enabled: isEditingEnabled,
                    decoration: InputDecoration(
                      labelText: OccasionSettingsStrings.link,
                      helperText: FormStrings.publicLinkHistoryHelp,
                      helperMaxLines: 3,
                    ),
                    validator: (value) {
                      if (value == null || value.isEmpty) {
                        return OccasionSettingsStrings.linkIsRequired;
                      }
                      if (value != savedLink && !isValidPublicSlug(value)) {
                        return FormStrings.validationLinkInvalidChars;
                      }
                      return null;
                    },
                    onChanged: onLinkChanged,
                    onSaved: onLinkSaved),
                const SizedBox(height: 12),
                ValueListenableBuilder<TextEditingValue>(
                    valueListenable: linkController,
                    builder: (_, value, __) => PublicLink(
                        link: value.text, savedLink: savedLink, isForm: false)),
                const SizedBox(height: 24),
              ],
              TextFormField(
                controller: replyToEmailController,
                enabled: isEditingEnabled,
                decoration: InputDecoration(
                  labelText: OccasionSettingsStrings.labelReplyToEmail,
                  floatingLabelBehavior: FloatingLabelBehavior.always,
                  hintText: (RightsService.currentUnit()
                                  ?.data?[Tb.units.data_reply_to] as String?)
                              ?.isNotEmpty ==
                          true
                      ? "${OccasionSettingsStrings.defaultValue}: ${RightsService.currentUnit()?.data?[Tb.units.data_reply_to]}"
                      : null,
                  border: const OutlineInputBorder(),
                  helperText: OccasionSettingsStrings.helperReplyToEmail,
                  helperMaxLines: 3,
                ),
                keyboardType: TextInputType.emailAddress,
                validator: (val) {
                  if (val == null || val.isEmpty) return null;
                  return EmailValidation.validator(
                      errorText:
                          OccasionSettingsStrings.validationEmailInvalid)(val);
                },
              ),
              const SizedBox(height: 16),
              if (allTimezones.isNotEmpty)
                _TimezoneAutocomplete(
                  selectedTimezone: selectedTimezone,
                  allTimezones: allTimezones,
                  isEditingEnabled: isEditingEnabled,
                  onTimezoneSelected: onTimezoneSelected,
                )
              else
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 12.0),
                  child: Text(OccasionSettingsStrings.timezonesLoading),
                ),
              const SizedBox(height: 16),
            ],
          ),
        ),
      ],
    );
  }
}

class _TimezoneAutocomplete extends StatelessWidget {
  final String? selectedTimezone;
  final List<String> allTimezones;
  final bool isEditingEnabled;
  final ValueChanged<String> onTimezoneSelected;

  const _TimezoneAutocomplete({
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
          return option
              .toLowerCase()
              .contains(textEditingValue.text.toLowerCase());
        });
      },
      onSelected: onTimezoneSelected,
      fieldViewBuilder: (BuildContext context,
          TextEditingController fieldTextEditingController,
          FocusNode fieldFocusNode,
          VoidCallback onFieldSubmitted) {
        return TextFormField(
          controller: fieldTextEditingController,
          focusNode: fieldFocusNode,
          enabled: isEditingEnabled,
          decoration: InputDecoration(
            labelText: OccasionSettingsStrings.timezone,
            border: const OutlineInputBorder(),
            suffixIcon:
                fieldTextEditingController.text.isNotEmpty && isEditingEnabled
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
      optionsViewBuilder: (BuildContext context,
          AutocompleteOnSelected<String> onSelected, Iterable<String> options) {
        return Align(
          alignment: Alignment.topLeft,
          child: Material(
            elevation: 4.0,
            child: ConstrainedBox(
              constraints: BoxConstraints(
                  maxHeight: 300,
                  maxWidth: MediaQuery.of(context).size.width - 40 > 0
                      ? MediaQuery.of(context).size.width - 40
                      : 300),
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
