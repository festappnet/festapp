import 'package:fstapp/data_services/rights_service.dart';
import 'package:fstapp/components/features/feature_constants.dart';
import 'package:fstapp/components/features/feature_service.dart';
import 'package:fstapp/components/eshop/order_item_strings.dart';
import 'package:festapp_core/forms.dart';
import 'package:flutter/material.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:fstapp/components/_shared/common_strings.dart';
import 'package:fstapp/components/forms/db_forms.dart';
import 'package:fstapp/components/html/html_helper.dart';
import 'package:fstapp/theme_config.dart';
import 'package:fstapp/components/html/html_view.dart';

import '../models/form_field_draft.dart';
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
  final bool editingEnabled;
  final bool expandProducts;
  const FormFieldsGenerator(
      {super.key,
      required this.bundle,
      this.onChanged,
      this.editingEnabled = true,
      this.expandProducts = false});

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
        .where((f) => f.definition.isTicketField != true)
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
        .where((f) => f.definition.isTicketField != true)
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
        if (!widget.editingEnabled || RightsService.isDemoReadOnly) return;
        _refresh(() {
          if (oldIndex < newIndex) newIndex -= 1;
          final item = topLevelFields.removeAt(oldIndex);
          topLevelFields.insert(newIndex, item);

          // Use the form from the bundle
          final form = widget.bundle.form;
          final updatedList = <FormFieldDraft>[];
          updatedList.addAll(topLevelFields);
          updatedList.addAll(
            form.relatedFields.where((f) => f.definition.isTicketField == true),
          );
          form.relatedFields = updatedList;

          for (int i = 0; i < form.relatedFields.length; i++) {
            form.relatedFields[i].definition =
                form.relatedFields[i].definition.copyWith(order: i);
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

  Widget _buildFieldItem(
    BuildContext context,
    int index,
    FormFieldDraft field,
    List<FormFieldDraft> displayList,
  ) {
    final isProduct = field.definition.type == FormMetadata.fieldTypeTicket ||
        field.definition.type == FormMetadata.fieldTypeProductType;
    final isSelected =
        selectedIndex == index || widget.expandProducts && isProduct;
    final effectiveOpacity =
        (field.definition.isHidden ?? false) ? kHiddenOpacity : 1.0;

    return GestureDetector(
      key: field.definition.id != null
          ? ValueKey(field.definition.id)
          : ObjectKey(field),
      onTap: () {
        if (!isSelected) {
          setState(() {
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
            child:
                Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              if (widget.expandProducts && isProduct) ...[
                Text(FormStrings.productsAndPrices,
                    style: Theme.of(context).textTheme.titleMedium),
                const SizedBox(height: 12),
              ],
              if (isSelected)
                _buildFieldItemSelected(field, displayList, index)
              else
                _buildFieldItemNonSelected(field),
            ]),
          ),
        ),
      ),
    );
  }

  Widget _selectionOptionsError() => Padding(
        padding: const EdgeInsets.only(top: 8),
        child: Semantics(
          liveRegion: true,
          child: Text(FormStrings.selectionOptionsRequired,
              style: TextStyle(color: Theme.of(context).colorScheme.error)),
        ),
      );

  Widget _buildFieldItemNonSelected(FormFieldDraft field) {
    final icon = FormHelper.fieldTypeIcons[field.definition.type];
    final bool hidden = field.definition.isHidden ?? false;
    final requiredStar = (field.definition.isRequired ?? false)
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
    final displayTitle = (field.definition.title?.isNotEmpty ?? false)
        ? field.definition.title!
        : FormHelper.fieldTypeToLocale(field.definition.type!);

    final fieldContent = _buildAnswerWidget(context, field, false);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            if (icon != null) ...[
              Icon(
                icon,
                size: 24,
                color: Theme.of(context).colorScheme.primary,
              ),
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
        if (!HtmlHelper.isHtmlEmptyOrNull(field.definition.description))
          Column(
            children: [
              HtmlView(html: field.definition.description!, fontSize: 14),
              const SizedBox(height: 16),
            ],
          ),
        fieldContent,
        if (field.hasInvalidSelectionOptions) _selectionOptionsError(),
      ],
    );
  }

  Widget _buildFieldItemSelected(
    FormFieldDraft field,
    List<FormFieldDraft> displayList,
    int index,
  ) {
    if (!widget.editingEnabled || RightsService.isDemoReadOnly) {
      return _buildFieldItemNonSelected(field);
    }
    final isTicket = field.definition.type == FormMetadata.fieldTypeTicket;
    final String defaultDescription = CommonStrings.description;
    final form = widget.bundle.form;
    void deleteField() {
      if (!field.definition.canDelete) return;
      _refresh(() {
        displayList.remove(field);
        form.removeField(field);
        if (selectedIndex == index) selectedIndex = null;
      });
    }

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
              Icon(
                FormHelper.fieldTypeIcons[FormMetadata.fieldTypeTicket],
                size: 24,
                color: Theme.of(context).colorScheme.primary,
              ),
              const SizedBox(width: 8),
              Text(
                OrderItemStrings.itemSingular,
                style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.bold,
                      color: Theme.of(context).colorScheme.primary,
                    ),
              ).tr(),
            ],
          )
        else ...[
          TextFormField(
            style: Theme.of(context).textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.bold,
                  color: Theme.of(context).colorScheme.primary,
                ),
            decoration: InputDecoration(
              border: const UnderlineInputBorder(),
              hintText:
                  FormHelper.fieldTypeToLocale(field.definition.type ?? ''),
              contentPadding: const EdgeInsets.symmetric(vertical: 8),
            ),
            initialValue: field.definition.title,
            onChanged: (value) {
              field.definition = field.definition.copyWith(title: value);
              widget.onChanged?.call();
            },
          ),
          if (!HtmlHelper.isHtmlEmptyOrNull(field.definition.description))
            Column(
              children: [
                DescriptionWithEdit(
                  description: field.definition.description!,
                  defaultDescription: defaultDescription,
                  onDescriptionChanged: (newDescription) {
                    _refresh(() {
                      field.definition = field.definition
                          .copyWith(description: newDescription);
                    });
                  },
                  occasionId: form.definition.occasionId!,
                ),
                const SizedBox(height: 16),
              ],
            ),
        ],
        _buildAnswerWidget(context, field, true),
        if (field.hasInvalidSelectionOptions) _selectionOptionsError(),
        const SizedBox(height: 16),
        if (!RightsService.isDemoReadOnly)
          _FieldControlsBar(
            controls: [
              if (!isTicket &&
                  field.definition.type != FormMetadata.fieldTypeEmail)
                SizedBox(
                  width: 150,
                  child: PopupMenuButton<String>(
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 8,
                      ),
                      decoration: BoxDecoration(
                        border: Border.all(color: Colors.grey),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Row(
                        children: [
                          Icon(
                              FormHelper.fieldTypeIcons[field.definition.type]),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              FormHelper.fieldTypeToLocale(
                                  field.definition.type!),
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        ],
                      ),
                    ),
                    itemBuilder: (context) => _availableFieldTypes
                        .map(
                          (entry) => PopupMenuItem(
                            value: entry,
                            child: Row(
                              children: [
                                Icon(FormHelper.fieldTypeIcons[entry]),
                                const SizedBox(width: 8),
                                Text(FormHelper.fieldTypeToLocale(entry)),
                              ],
                            ),
                          ),
                        )
                        .toList(),
                    onSelected: (newType) => _refresh(() {
                      if (!((field.definition.type ==
                                  FormMetadata.fieldTypeSelectOne ||
                              field.definition.type ==
                                  FormMetadata.fieldTypeSelectMany) &&
                          (newType == FormMetadata.fieldTypeSelectOne ||
                              newType == FormMetadata.fieldTypeSelectMany))) {
                        field.definition =
                            field.definition.copyWith(data: null);
                        field.options.clear();
                      }
                      field.definition =
                          field.definition.copyWith(type: newType);
                      if ((field.definition.title?.isEmpty ?? true)) {
                        field.definition = field.definition.copyWith(
                            title: FormHelper.fieldTypeToLocale(newType));
                      }
                      if (FormMetadata.isAlwaysRequired(newType)) {
                        field.definition =
                            field.definition.copyWith(isRequired: true);
                      }
                    }),
                  ),
                ),
              if (isTicket)
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      CommonStrings.note,
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                    const SizedBox(width: 4),
                    TicketEditorWidgets.buildTicketNoteCheckbox(
                      context,
                      form,
                      () {
                        _refresh(() {});
                      },
                    ),
                  ],
                ),
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    FormStrings.requiredLabel,
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                  Checkbox(
                    value: FormMetadata.isAlwaysRequired(
                            field.definition.type ?? '') ||
                        (field.definition.isRequired ?? false),
                    onChanged: FormMetadata.isAlwaysRequired(
                            field.definition.type ?? '')
                        ? null
                        : (value) => _refresh(() => field.definition =
                            field.definition.copyWith(isRequired: value)),
                  ),
                ],
              ),
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    FormStrings.show,
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                  Switch(
                    value: !(field.definition.isHidden ?? false),
                    onChanged:
                        (field.definition.type == FormMetadata.fieldTypeEmail ||
                                isTicket)
                            ? null
                            : (value) => _refresh(() => field.definition =
                                field.definition.copyWith(isHidden: !value)),
                  ),
                ],
              ),
            ],
            buildActions: (isCompact) => Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                // Popup Menu (Description & Deposit)
                PopupMenuButton<String>(
                  onSelected: (value) {
                    if (value == "add_description") {
                      _refresh(() {
                        if (HtmlHelper.isHtmlEmptyOrNull(
                            field.definition.description)) {
                          field.definition = field.definition
                              .copyWith(description: defaultDescription);
                        }
                      });
                    } else if (value == "delete_field") {
                      deleteField();
                    } else if (value == "show_deposit_description") {
                      _refresh(() {
                        field.definition = field.definition
                            .copyWith(data: field.definition.data ?? {});
                        var current = field.definition.data![
                                TicketHolder.metaShowDepositDescription] ??
                            true;
                        field.definition = field.definition.copyWith(data: {
                          ...?field.definition.data,
                          TicketHolder.metaShowDepositDescription: !current
                        });
                      });
                    }
                  },
                  itemBuilder: (context) {
                    List<PopupMenuEntry<String>> items = [];
                    // Add Description Option
                    items.add(
                      PopupMenuItem<String>(
                        value: "add_description",
                        child: Text(FormStrings.addDescription),
                      ),
                    );

                    // Ticket Specific Options
                    if (isTicket &&
                        FeatureService.isFeatureEnabled(
                            FeatureConstants.deposit)) {
                      bool showDeposit = field.definition
                              .data?[TicketHolder.metaShowDepositDescription] ??
                          true;
                      items.add(const PopupMenuDivider());
                      items.add(
                        CheckedPopupMenuItem<String>(
                          value: "show_deposit_description",
                          checked: showDeposit,
                          child: Text(FormStrings.showDepositDescription),
                        ),
                      );
                    }
                    if (isCompact) {
                      items.add(const PopupMenuDivider());
                      items.add(
                        PopupMenuItem<String>(
                          value: "delete_field",
                          enabled: field.definition.canDelete,
                          child: Tooltip(
                            message: field.definition.canDelete
                                ? CommonStrings.delete
                                : FormStrings.deletionReason(
                                    field.definition.deleteBlockedReason,
                                  ),
                            child: Row(
                              children: [
                                const Icon(Icons.delete_outline),
                                const SizedBox(width: 12),
                                Text(CommonStrings.delete),
                              ],
                            ),
                          ),
                        ),
                      );
                    }
                    return items;
                  },
                  icon: const Icon(Icons.more_vert),
                ),
                if (!isCompact)
                  IconButton(
                    tooltip: field.definition.canDelete
                        ? CommonStrings.delete
                        : FormStrings.deletionReason(
                            field.definition.deleteBlockedReason),
                    icon: const Icon(Icons.delete),
                    onPressed: field.definition.canDelete ? deleteField : null,
                  ),
              ],
            ),
          ),
      ],
    );
  }

  Widget _buildAnswerWidget(
    BuildContext context,
    FormFieldDraft field,
    bool isEditable,
  ) {
    final form = widget.bundle.form;
    switch (field.definition.type) {
      case FormMetadata.fieldTypeTicket:
        return isEditable
            ? TicketEditorWidgets.buildTicketEditor(
                context,
                form,
                field,
                widget.bundle.productTypes,
                () {
                  _refresh(() {});
                },
              )
            : TicketEditorWidgets.buildTicketEditorReadOnly(
                context,
                form,
                field,
              );
      case FormMetadata.fieldTypeSelectOne:
        return isEditable
            ? SelectOneEditor.buildSelectOneEditor(
                context,
                field,
                form.definition.occasionId,
                onChanged: () => _refresh(() {}),
              )
            : SelectOneEditor.buildSelectOneReadOnly(context, field);
      case FormMetadata.fieldTypeSelectMany:
        return isEditable
            ? SelectManyEditor.buildSelectManyEditor(
                context,
                field,
                form.definition.occasionId,
                onChanged: () => _refresh(() {}),
              )
            : SelectManyEditor.buildSelectManyReadOnly(context, field);
      case FormMetadata.fieldTypeSex:
        return SexEditor.buildSexFieldReadOnly(context, field);
      case FormMetadata.fieldTypeBirthDate:
        return isEditable
            ? BirthDateEditor.buildBirthDateEditor(
                context,
                field,
                form.definition.occasionId,
                onChanged: widget.onChanged,
              )
            : BirthDateEditor.buildBirthDateReadOnly(context, field);
      case FormMetadata.fieldTypeIdDocument:
        return isEditable
            ? IdDocumentEditor.buildIdDocumentEditor(
                context,
                field,
                form.definition.occasionId,
                onChanged: widget.onChanged,
              )
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
        widget.bundle.form.relatedFields.map((f) => f.definition.type).toList();
    return FormHelper.fieldTypeIcons.keys.where((type) {
      if ([
        FormMetadata.fieldTypeText,
        FormMetadata.fieldTypeSelectOne,
        FormMetadata.fieldTypeSelectMany,
        FormMetadata.fieldTypePhone,
      ].contains(type)) {
        return true;
      }
      return !existingTypes.contains(type);
    }).toList();
  }
}

class _FieldControlsBar extends StatefulWidget {
  final List<Widget> controls;
  final Widget Function(bool isCompact) buildActions;

  const _FieldControlsBar({required this.controls, required this.buildActions});

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
    return LayoutBuilder(
      builder: (context, constraints) => Row(
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
            child: widget.buildActions(constraints.maxWidth < 600),
          ),
        ],
      ),
    );
  }
}
