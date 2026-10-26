import 'package:material_ui/material_ui.dart';
import 'package:fstapp/components/forms/models/form_field_draft.dart';
import 'package:fstapp/components/forms/models/form_option_draft.dart';
import 'package:fstapp/components/users/user_info_model.dart';
import 'package:fstapp/components/forms/widgets_view/form_helper.dart';
import 'description_tooltip.dart';

class SexEditor {
  static Widget buildSexFieldReadOnly(
      BuildContext context, FormFieldDraft field) {
    final options = [
      FormOptionDraft(UserInfoModel.sexes[0], FormHelper.maleLabel()),
      FormOptionDraft(UserInfoModel.sexes[1], FormHelper.femaleLabel()),
    ];
    return Column(
      children: options.map((option) {
        return Row(
          children: [
            Radio<String>(
              value: option.title,
              groupValue: null,
              onChanged: null,
            ),
            Text(option.title),
            if (option.description != null &&
                option.description!.trim().isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(left: 8.0),
                child: Row(
                  children: [
                    DescriptionTooltip(
                      description: option.description!,
                      child: const Icon(Icons.description, size: 16),
                    ),
                  ],
                ),
              ),
          ],
        );
      }).toList(),
    );
  }
}
