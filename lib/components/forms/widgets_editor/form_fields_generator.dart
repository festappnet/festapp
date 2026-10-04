import 'package:flutter/material.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:fstapp/components/_shared/common_strings.dart';
import 'package:fstapp/components/forms/db_forms.dart';
import 'package:fstapp/components/eshop/orders_strings.dart';
import 'package:fstapp/components/html/html_helper.dart';
import 'package:fstapp/theme_config.dart';
import 'package:fstapp/components/html/html_view.dart';
import '../models/form_field_model.dart';
import '../widgets_view/form_helper.dart';
import 'birth_date_editor.dart';
import 'description_with_edit.dart';
import 'sex_editor.dart';
import 'ticket_editor_widgets.dart';
import 'select_one_editor.dart';
import 'select_many_editor.dart';
import 'id_document_editor.dart';
import '../form_strings.dart';
import 'package:fstapp/components/forms/models/holder_models/ticket_holder.dart';

// Define kHiddenOpacity if it's not globally available from form_editor_content.dart
const double kHiddenOpacity = 0.5;

class FormFieldsGenerator extends StatefulWidget {
  final FormEditBundle bundle;
  final VoidCallback? onChanged;
  const FormFieldsGenerator({super.key, required this.bundle, this.onChanged});

  @override
  _FormFieldsGeneratorState createState() => _FormFieldsGeneratorState();
}

class _FormFieldsGeneratorState extends State<FormFieldsGenerator> {
  int? selectedIndex;
  void _refresh(VoidCallback change) {
    setState(change);
    widget.onChanged?.call();
  }

  @override
  void initState() {
    super.initState();
    // Use the form from the bundle
    final topLevelFields = widget.bundle.form.relatedFields
        .where((f) => f.isTicketField != true)
        .toList();
    if (topLevelFields.isNotEmpty) {
      selectedIndex = 0;
    }
  }

  @override
  Widget build(BuildContext context) {
    return _buildFieldsList();
  }

  Widget _buildFieldsList() {
    // Use the form from the bundle
    final topLevelFields = widget.bundle.form.relatedFields
        .where((f) => f.isTicketField != true)
        .toList();

    return ReorderableListView.builder(
      shrinkWrap: true,
      primary: false,
      buildDefaultDragHandles: false,
      itemCount: topLevelFields.length,
      itemBuilder: (context, index) {
        final field = topLevelFields[index];
        return _buildFieldItem(context, index, field, topLevelFields);
      },
      onReorder: (oldIndex, newIndex) {
        _refresh(() {
          if (oldIndex < newIndex) newIndex -= 1;
          final item = topLevelFields.removeAt(oldIndex);
          topLevelFields.insert(newIndex, item);

          // Use the form from the bundle
          final form = widget.bundle.form;
          final updatedList = <FormFieldModel>[];
          updatedList.addAll(topLevelFields);
          updatedList
              .addAll(form.relatedFields.where((f) => f.isTicketField == true));
          form.relatedFields = updatedList;

          for (int i = 0; i < form.relatedFields.length; i++) {
            form.relatedFields[i].order = i;
          }

          if (selectedIndex == oldIndex) {
            selectedIndex = newIndex;
          } else if (selectedIndex != null &&
              selectedIndex! >= newIndex &&
              selectedIndex! < oldIndex) {
            selectedIndex = selectedIndex! + 1;
          }
        });
      },
    );
  }

  Widget _buildFieldItem(BuildContext context, int index, FormFieldModel field,
      List<FormFieldModel> displayList) {
    final isSelected = (selectedIndex == index);
    final effectiveOpacity = (field.isHidden ?? false) ? kHiddenOpacity : 1.0;

    return GestureDetector(
      key: field.id != null ? ValueKey(field.id) : ObjectKey(field),
      onTap: () {
        if (!isSelected) {
          _refresh(() {
            selectedIndex = index;
          });
        }
      },
      child: Opacity(
        opacity: effectiveOpacity,
        child: Card(
          elevation: isSelected ? 4 : 2,
          margin: const EdgeInsets.symmetric(vertical: 4),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(8),
            side: BorderSide(
              color: isSelected
                  ? Theme.of(context).colorScheme.primary
                  : Colors.grey.withOpacity(0.3),
              width: isSelected ? 2 : 0,
            ),
          ),
          child: Padding(
            padding: const EdgeInsets.all(12.0),
            child: isSelected
                ? _buildFieldItemSelected(field, displayList, index)
                : _buildFieldItemNonSelected(field),
          ),
        ),
      ),
    );
  }

  Widget _buildFieldItemNonSelected(FormFieldModel field) {
    final icon = FormHelper.fieldTypeIcons[field.type];
    final bool hidden = field.isHidden ?? false;
    final requiredStar = (field.isRequired ?? false)
        ? TextSpan(
            text: ' *',
            style: TextStyle(color: ThemeConfig.redColor(context)),
          )
        : null;
    final titleStyle = hidden
        ? TextStyle(
            decoration: TextDecoration.lineThrough,
            color: Theme.of(context).colorScheme.primary,
            fontWeight: FontWeight.bold,
          )
        : TextStyle(
            color: Theme.of(context).colorScheme.primary,
            fontWeight: FontWeight.bold,
          );
    final displayTitle = (field.title?.isNotEmpty ?? false)
        ? field.title!
        : FormHelper.fieldTypeToLocale(field.type!);

    final fieldContent = _buildAnswerWidget(context, field, false);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            if (icon != null) ...[
              Icon(icon,
                  size: 24, color: Theme.of(context).colorScheme.primary),
              const SizedBox(width: 8),
            ],
            Flexible(
              child: RichText(
                text: TextSpan(
                  style: titleStyle,
                  text: displayTitle,
                  children: [if (requiredStar != null) requiredStar],
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        if (!HtmlHelper.isHtmlEmptyOrNull(field.description))
          Column(
            children: [
              HtmlView(
                html: field.description!,
                fontSize: 14,
              ),
              const SizedBox(height: 16),
            ],
          ),
        fieldContent,
      ],
    );
  }

  Widget _buildFieldItemSelected(
      FormFieldModel field, List<FormFieldModel> displayList, int index) {
    final isTicket = field.type == FormHelper.fieldTypeTicket;
    final String defaultDescription = CommonStrings.description;
    final form = widget.bundle.form;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Center(
          child: ReorderableDragStartListener(
            index: index,
            child: const Icon(Icons.drag_handle, color: Colors.grey, size: 24),
          ),
        ),
        const SizedBox(height: 8),
        if (isTicket)
          Row(
            children: [
              Icon(FormHelper.fieldTypeIcons[FormHelper.fieldTypeTicket],
                  size: 24, color: Theme.of(context).colorScheme.primary),
              const SizedBox(width: 8),
              Text(OrdersStrings.itemSingular,
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.bold,
                          color: Theme.of(context).colorScheme.primary))
                  .tr(),
            ],
          )
        else ...[
          TextFormField(
            style: Theme.of(context).textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.bold,
                color: Theme.of(context).colorScheme.primary),
            decoration: InputDecoration(
              border: const UnderlineInputBorder(),
              hintText: FormHelper.fieldTypeToLocale(field.type ?? ''),
              contentPadding: const EdgeInsets.symmetric(vertical: 8),
            ),
            initialValue: field.title,
            onChanged: (value) {
              field.title = value;
              widget.onChanged?.call();
            },
          ),
          if (!HtmlHelper.isHtmlEmptyOrNull(field.description))
            Column(
              children: [
                DescriptionWithEdit(
                  description: field.description!,
                  defaultDescription: defaultDescription,
                  onDescriptionChanged: (newDescription) {
                    _refresh(() {
                      field.description = newDescription;
                    });
                  },
                  occasionId: form.occasionId!,
                ),
                const SizedBox(height: 16),
              ],
            ),
        ],
        _buildAnswerWidget(context, field, true),
        const SizedBox(height: 16),
        _FieldControlsBar(
          controls: [
            if (!isTicket && field.type != FormHelper.fieldTypeEmail)
              SizedBox(
                width: 150,
                child: PopupMenuButton<String>(
                  child: Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                    decoration: BoxDecoration(
                      border: Border.all(color: Colors.grey),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Row(
                      children: [
                        Icon(FormHelper.fieldTypeIcons[field.type]),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(FormHelper.fieldTypeToLocale(field.type!),
                              overflow: TextOverflow.ellipsis),
                        ),
                      ],
                    ),
                  ),
                  itemBuilder: (context) => _availableFieldTypes
                      .map((entry) => PopupMenuItem(
                            value: entry,
                            child: Row(
                              children: [
                                Icon(FormHelper.fieldTypeIcons[entry]),
                                const SizedBox(width: 8),
                                Text(FormHelper.fieldTypeToLocale(entry)),
                              ],
                            ),
                          ))
                      .toList(),
                  onSelected: (newType) => _refresh(() {
                    if (!((field.type == FormHelper.fieldTypeSelectOne ||
                            field.type == FormHelper.fieldTypeSelectMany) &&
                        (newType == FormHelper.fieldTypeSelectOne ||
                            newType == FormHelper.fieldTypeSelectMany))) {
                      field.data = null;
                      field.options.clear();
                    }
                    field.type = newType;
                    if ((field.title?.isEmpty ?? true)) {
                      field.title = FormHelper.fieldTypeToLocale(newType);
                    }
                    if (FormHelper.isAlwaysRequired(newType)) {
                      field.isRequired = true;
                    }
                  }),
                ),
              ),
            if (isTicket)
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(CommonStrings.note,
                      style: Theme.of(context).textTheme.bodySmall),
                  const SizedBox(width: 4),
                  TicketEditorWidgets.buildTicketNoteCheckbox(context, form,
                      () {
                    _refresh(() {});
                  }),
                ],
              ),
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(FormStrings.requiredLabel,
                    style: Theme.of(context).textTheme.bodySmall),
                Checkbox(
                  value: FormHelper.isAlwaysRequired(field.type ?? '') ||
                      (field.isRequired ?? false),
                  onChanged: FormHelper.isAlwaysRequired(field.type ?? '')
                      ? null
                      : (value) => _refresh(() => field.isRequired = value),
                ),
              ],
            ),
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(FormStrings.show,
                    style: Theme.of(context).textTheme.bodySmall),
                Switch(
                  value: !(field.isHidden ?? false),
                  onChanged:
                      (field.type == FormHelper.fieldTypeEmail || isTicket)
                          ? null
                          : (value) => _refresh(() => field.isHidden = !value),
                ),
              ],
            ),
          ],
          actions: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Popup Menu (Description & Deposit)
              PopupMenuButton<String>(
                onSelected: (value) {
                  if (value == "add_description") {
                    _refresh(() {
                      if (HtmlHelper.isHtmlEmptyOrNull(field.description)) {
                        field.description = defaultDescription;
                      }
                    });
                  } else if (value == "show_deposit_description") {
                    _refresh(() {
                      field.data ??= {};
                      var current = field
                              .data![TicketHolder.metaShowDepositDescription] ??
                          true;
                      field.data![TicketHolder.metaShowDepositDescription] =
                          !current;
                    });
                  }
                },
                itemBuilder: (context) {
                  List<PopupMenuEntry<String>> items = [];
                  // Add Description Option
                  items.add(PopupMenuItem<String>(
                    value: "add_description",
                    child: Text(FormStrings.addDescription),
                  ));

                  // Ticket Specific Options
                  if (isTicket) {
                    bool showDeposit =
                        field.data?[TicketHolder.metaShowDepositDescription] ??
                            true;
                    items.add(const PopupMenuDivider());
                    items.add(CheckedPopupMenuItem<String>(
                      value: "show_deposit_description",
                      checked: showDeposit,
                      child: Text(FormStrings.showDepositDescription),
                    ));
                  }
                  return items;
                },
                icon: const Icon(Icons.more_vert),
              ),
              IconButton(
                tooltip: field.canDelete
                    ? CommonStrings.delete
                    : FormStrings.deletionReason(field.deleteBlockedReason),
                icon: const Icon(Icons.delete),
                onPressed: !field.canDelete
                    ? null
                    : () {
                        _refresh(() {
                          displayList.remove(field);
                          widget.bundle.form.removeField(field);
                          if (selectedIndex == index) {
                            selectedIndex = null;
                          }
                        });
                      },
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildAnswerWidget(
      BuildContext context, FormFieldModel field, bool isEditable) {
    final form = widget.bundle.form;
    switch (field.type) {
      case FormHelper.fieldTypeTicket:
        return isEditable
            ? TicketEditorWidgets.buildTicketEditor(
                context, form, field, widget.bundle.productTypes, () {
                _refresh(() {});
              })
            : TicketEditorWidgets.buildTicketEditorReadOnly(
                context, form, field);
      case FormHelper.fieldTypeSelectOne:
        return isEditable
            ? SelectOneEditor.buildSelectOneEditor(
                context, field, form.occasionId,
                onChanged: widget.onChanged)
            : SelectOneEditor.buildSelectOneReadOnly(context, field);
      case FormHelper.fieldTypeSelectMany:
        return isEditable
            ? SelectManyEditor.buildSelectManyEditor(
                context, field, form.occasionId,
                onChanged: widget.onChanged)
            : SelectManyEditor.buildSelectManyReadOnly(context, field);
      case FormHelper.fieldTypeSex:
        return SexEditor.buildSexFieldReadOnly(context, field);
      case FormHelper.fieldTypeBirthDate:
        return isEditable
            ? BirthDateEditor.buildBirthDateEditor(
                context, field, form.occasionId,
                onChanged: widget.onChanged)
            : BirthDateEditor.buildBirthDateReadOnly(context, field);
      case FormHelper.fieldTypeIdDocument:
        return isEditable
            ? IdDocumentEditor.buildIdDocumentEditor(
                context, field, form.occasionId,
                onChanged: widget.onChanged)
            : IdDocumentEditor.buildIdDocumentReadOnly(context, field);
      default:
        if (isEditable) {
          return Padding(
            padding: const EdgeInsets.only(top: 8.0),
            child: InputDecorator(
              decoration: const InputDecoration(
                border: UnderlineInputBorder(),
                contentPadding: EdgeInsets.symmetric(vertical: 8),
              ),
              child: Text(
                FormStrings.answerText,
                style: Theme.of(context)
                    .textTheme
                    .bodyLarge
                    ?.copyWith(color: Theme.of(context).hintColor),
              ),
            ),
          );
        } else {
          return Text(
            FormStrings.answerText,
            style: Theme.of(context)
                .textTheme
                .bodyLarge
                ?.copyWith(color: Colors.grey),
          );
        }
    }
  }

  List<String> get _availableFieldTypes {
    final existingTypes =
        widget.bundle.form.relatedFields.map((f) => f.type).toList();
    return FormHelper.fieldTypeIcons.keys.where((type) {
      if ([
        FormHelper.fieldTypeText,
        FormHelper.fieldTypeSelectOne,
        FormHelper.fieldTypeSelectMany,
        FormHelper.fieldTypePhone,
      ].contains(type)) {
        return true;
      }
      return !existingTypes.contains(type);
    }).toList();
  }
}

class _FieldControlsBar extends StatefulWidget {
  final List<Widget> controls;
  final Widget actions;

  const _FieldControlsBar({required this.controls, required this.actions});

  @override
  State<_FieldControlsBar> createState() => _FieldControlsBarState();
}

class _FieldControlsBarState extends State<_FieldControlsBar> {
  final _scrollController = ScrollController();

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: LayoutBuilder(
            builder: (context, constraints) => Scrollbar(
              controller: _scrollController,
              thumbVisibility: true,
              thickness: 3,
              child: SingleChildScrollView(
                controller: _scrollController,
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.only(bottom: 8),
                child: ConstrainedBox(
                  constraints: BoxConstraints(minWidth: constraints.maxWidth),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      for (final control in widget.controls)
                        Padding(
                          padding: const EdgeInsets.only(right: 16),
                          child: control,
                        ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
        Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: widget.actions,
        ),
      ],
    );
  }
}
