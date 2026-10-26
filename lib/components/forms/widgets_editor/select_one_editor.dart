import 'package:fstapp/components/html/rich_html_editor_controller.dart';
import 'package:material_ui/material_ui.dart';
import 'package:fstapp/components/forms/form_strings.dart';
import 'package:fstapp/components/forms/models/form_field_draft.dart';
import 'package:fstapp/components/forms/models/form_option_draft.dart';

import 'package:festapp_core/forms.dart';
import 'option_editor_dialog.dart';
import 'description_tooltip.dart';

class SelectOneEditor {
  static Widget buildSelectOneReadOnly(
      BuildContext context, FormFieldDraft field) {
    final options = field.options;
    if (options.isEmpty) {
      return Text(
        FormStrings.noOptions,
        style: Theme.of(context).textTheme.bodyMedium,
      );
    }
    final currentDefault = DefaultValueHelper.readString(field.definition.data);
    return Column(
      children: options.map((option) {
        return Row(
          children: [
            Radio<String>(
              value: option.title,
              groupValue: currentDefault,
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

  static Widget buildSelectOneEditor(
      BuildContext context, FormFieldDraft field, int? occasionId,
      {VoidCallback? onChanged}) {
    final optionsController = TextEditingController();
    return StatefulBuilder(builder: (ctx, updateLocal) {
      void setLocal(VoidCallback change) {
        updateLocal(change);
        onChanged?.call();
      }

      final currentDefault =
          DefaultValueHelper.readString(field.definition.data);
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(FormStrings.options,
              style: Theme.of(context).textTheme.titleSmall),
          const SizedBox(height: 2),
          Text(
            FormStrings.defaultSelectionHintSingle,
            style: Theme.of(context).textTheme.bodySmall,
          ),
          const SizedBox(height: 8),
          Column(
            children: field.options.map((FormOptionDraft formOption) {
              final optionController =
                  TextEditingController(text: formOption.title);
              return Row(
                children: [
                  Radio<String>(
                    value: formOption.title,
                    groupValue: currentDefault,
                    onChanged: (value) {
                      field.definition = field.definition.copyWith(
                          data: DefaultValueHelper.write(
                              field.definition.data, value));
                      setLocal(() {});
                    },
                  ),
                  Expanded(
                    child: TextFormField(
                      controller: optionController,
                      decoration: InputDecoration(
                        border: const UnderlineInputBorder(),
                        suffixIcon: formOption.description != null &&
                                formOption.description!.trim().isNotEmpty
                            ? DescriptionTooltip(
                                description: formOption.description!,
                                child: Icon(Icons.description, size: 20),
                              )
                            : null,
                      ),
                      onChanged: (value) {
                        final oldTitle = formOption.title;
                        formOption.title = value;
                        field.definition = field.definition.copyWith(
                            data: DefaultValueHelper.rename(
                                field.definition.data, oldTitle, value));
                      },
                    ),
                  ),
                  PopupMenuButton<String>(
                    onSelected: (value) {
                      if (value == 'additional_settings') {
                        final htmlCoordinator =
                            HtmlEditingScope.maybeOf(context);
                        showDialog(
                          context: context,
                          builder: (context) => OptionDetailEditorDialog(
                            option: formOption,
                            coordinator: htmlCoordinator,
                            occasionId: occasionId,
                          ),
                        ).then((_) {
                          setLocal(() {});
                        });
                      }
                    },
                    itemBuilder: (BuildContext context) =>
                        <PopupMenuEntry<String>>[
                      PopupMenuItem<String>(
                        value: 'additional_settings',
                        child: Text(FormStrings.additionalSettings),
                      ),
                    ],
                    icon: const Icon(Icons.more_vert),
                  ),
                  IconButton(
                    icon: const Icon(Icons.delete),
                    onPressed: () {
                      final removedTitle = formOption.title;
                      field.options.remove(formOption);
                      field.definition = field.definition.copyWith(
                          data: DefaultValueHelper.remove(
                              field.definition.data, removedTitle));
                      setLocal(() {});
                    },
                  ),
                ],
              );
            }).toList(),
          ),
          if (currentDefault != null)
            Padding(
              padding: const EdgeInsets.only(top: 4.0),
              child: TextButton.icon(
                icon: const Icon(Icons.clear, size: 16),
                label: Text(FormStrings.clearDefaultSelection),
                onPressed: () {
                  field.definition = field.definition.copyWith(
                      data: DefaultValueHelper.write(
                          field.definition.data, null));
                  setLocal(() {});
                },
              ),
            ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: optionsController,
                  decoration: InputDecoration(
                    hintText: FormStrings.enterOptionValue,
                    border: const UnderlineInputBorder(),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              IconButton(
                icon: const Icon(Icons.add),
                onPressed: () {
                  if (optionsController.text.isNotEmpty) {
                    final newOption = FormOptionDraft(
                      optionsController.text,
                      optionsController.text,
                    );
                    field.options.add(newOption);
                    optionsController.clear();
                    setLocal(() {});
                  }
                },
              ),
            ],
          ),
        ],
      );
    });
  }
}
