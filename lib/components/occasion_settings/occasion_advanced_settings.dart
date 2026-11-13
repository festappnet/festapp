import 'package:fstapp/components/forms/email_validation.dart';
import 'package:material_ui/material_ui.dart';
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
  final bool isEditingEnabled;
  final ValueChanged<String> onLinkChanged;
  final ValueChanged<String?> onLinkSaved;
  const OccasionAdvancedSettings({
    super.key,
    required this.linkController,
    this.savedLink,
    required this.replyToEmailController,
    required this.isEditingEnabled,
    required this.onLinkChanged,
    required this.onLinkSaved,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
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
            onSaved: onLinkSaved,
          ),
          const SizedBox(height: 12),
          ValueListenableBuilder<TextEditingValue>(
            valueListenable: linkController,
            builder: (_, value, __) => PublicLink(
              link: value.text,
              savedLink: savedLink,
              isForm: false,
            ),
          ),
          const SizedBox(height: 24),
        ],
        TextFormField(
          controller: replyToEmailController,
          enabled: isEditingEnabled,
          decoration: InputDecoration(
            labelText: OccasionSettingsStrings.labelReplyToEmail,
            floatingLabelBehavior: FloatingLabelBehavior.always,
            hintText:
                (RightsService.currentUnit()?.data?[Tb.units.data_reply_to]
                            as String?)
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
              errorText: OccasionSettingsStrings.validationEmailInvalid,
            )(val);
          },
        ),
      ],
    );
  }
}
