import 'package:fstapp/components/html/rich_html_editor_controller.dart';
import 'package:flutter/material.dart';
import 'package:fstapp/components/forms/form_strings.dart';
import 'package:fstapp/components/forms/models/form_field_model.dart';
import 'package:fstapp/components/forms/models/form_option_model.dart';

import 'default_value_helper.dart';
import 'option_editor_dialog.dart';
import 'description_tooltip.dart';

class SelectManyEditor {
  static Widget buildSelectManyReadOnly(
      BuildContext context, FormFieldModel field) {
    final options = field.options;
    if (options.isEmpty) {
      return Text(
        FormStrings.noOptions,
        style: Theme.of(context).textTheme.bodyMedium,
      );
    }
    final defaults = DefaultValueHelper.readList(field);
    return Column(
      children: options.map((option) {
        return Row(
          children: [
            Checkbox(
              value: defaults.contains(option.title),
              onChanged: null,
            ),
            Text(option.title),
            if (option.description != null &&
                option.description!.trim().isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(left: 8.0),
                child: DescriptionTooltip(
                  description: option.description!,
                  child: const Icon(Icons.description, size: 16),
                ),
              ),
          ],
        );
      }).toList(),
    );
  }

  static Widget buildSelectManyEditor(
      BuildContext context, FormFieldModel field, int? occasionId,
      {VoidCallback? onChanged}) {
    final optionsController = TextEditingController();
    return StatefulBuilder(builder: (ctx, updateLocal) {
      void setLocal(VoidCallback change) {
        updateLocal(change);
        onChanged?.call();
      }

      final defaults = DefaultValueHelper.readList(field);
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(FormStrings.options,
              style: Theme.of(context).textTheme.titleSmall),
          const SizedBox(height: 2),
          Text(
            FormStrings.defaultSelectionHintMulti,
            style: Theme.of(context).textTheme.bodySmall,
          ),
          const SizedBox(height: 8),
          Column(
            children: field.options.map((FormOptionModel formOption) {
              final optionController =
                  TextEditingController(text: formOption.title);
              return Row(
                children: [
                  Checkbox(
                    value: defaults.contains(formOption.title),
                    onChanged: (val) {
                      DefaultValueHelper.toggleInList(
                          field, formOption.title, val ?? false);
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
                        DefaultValueHelper.rename(field, oldTitle, value);
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
                      DefaultValueHelper.remove(field, removedTitle);
                      setLocal(() {});
                    },
                  ),
                ],
              );
            }).toList(),
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
                    final newOption = FormOptionModel(
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
