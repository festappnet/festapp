import 'package:fstapp/data_services/rights_service.dart';
import 'package:fstapp/components/features/feature_constants.dart';
import 'package:fstapp/components/features/feature_service.dart';
import 'package:fstapp/components/eshop/order_item_strings.dart';
import 'package:festapp_core/forms.dart';
import 'package:material_ui/material_ui.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:fstapp/components/_shared/common_strings.dart';
import 'package:fstapp/components/forms/db_forms.dart';
import 'package:fstapp/components/html/html_helper.dart';
import 'package:fstapp/theme_config.dart';
import 'package:fstapp/components/html/html_view.dart';

import '../models/form_field_draft.dart';
import '../widgets_view/form_helper.dart';
import 'birth_date_editor.dart';
import 'form_fields_navigation_controller.dart';
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
  final FormFieldsNavigationController? navigationController;
  const FormFieldsGenerator({
    super.key,
    required this.bundle,
    this.onChanged,
    this.editingEnabled = true,
    this.expandProducts = false,
    this.navigationController,
  });

  @override
  _FormFieldsGeneratorState createState() => _FormFieldsGeneratorState();
}

class _FormFieldsGeneratorState extends State<FormFieldsGenerator> {
  Object? _selectedIdentity;
  final Map<Object, GlobalKey> _anchors = {};
  bool _publicationPending = false;
  Object _identity(FormFieldDraft field) => field.definition.id ?? field;
  List<FormFieldDraft> get _topLevelFields => widget.bundle.form.relatedFields
      .where((field) => field.definition.isTicketField != true)
      .toList();

  void _publishNavigation() {
    final fields = _topLevelFields;
    final identities = fields.map(_identity).toSet();
    _anchors.removeWhere((identity, _) => !identities.contains(identity));
    if (!identities.contains(_selectedIdentity)) _selectedIdentity = null;
    widget.navigationController?.publish(this, [
      for (final field in fields)
        FormFieldNavigationItem(
          field: field,
          identity: _identity(field),
          title: field.definition.title?.trim().isNotEmpty == true
              ? field.definition.title!
              : FormHelper.fieldTypeToLocale(field.definition.type ?? ''),
        ),
    ], _selectedIdentity);
  }

  void _schedulePublication() {
    if (_publicationPending) return;
    _publicationPending = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _publicationPending = false;
      if (mounted) _publishNavigation();
    });
  }

  void _attachNavigation() {
    widget.navigationController?.attach(
      this,
      reveal: _revealField,
      clearSelection: () {
        setState(() => _selectedIdentity = null);
        _publishNavigation();
      },
    );
    _schedulePublication();
  }

  void _revealField(FormFieldDraft field) {
    final bundle = widget.bundle;
    if (!_topLevelFields.contains(field)) return;
    final identity = _identity(field);
    setState(() => _selectedIdentity = identity);
    _publishNavigation();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted ||
          !identical(bundle, widget.bundle) ||
          !_topLevelFields.contains(field))
        return;
      final target = _anchors[identity]?.currentContext;
      if (target != null) {
        Scrollable.ensureVisible(
          target,
          alignment: 0.1,
          duration: const Duration(milliseconds: 250),
        );
      }
    });
  }

  void _refresh(VoidCallback change) {
    setState(change);
    _publishNavigation();
    widget.onChanged?.call();
  }

  @override
  void initState() {
    super.initState();
    if (_topLevelFields.isNotEmpty) {
      _selectedIdentity = _identity(_topLevelFields.first);
    }
    _attachNavigation();
  }

  @override
  void didUpdateWidget(covariant FormFieldsGenerator oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(oldWidget.bundle, widget.bundle)) {
      _anchors.clear();
      _selectedIdentity = null;
    }
    if (oldWidget.navigationController != widget.navigationController) {
      oldWidget.navigationController?.detach(this);
      _attachNavigation();
    }
    _schedulePublication();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _schedulePublication();
  }

  @override
  void dispose() {
    widget.navigationController?.detach(this);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => _buildFieldsList();

  Widget _buildFieldsList() {
    // Use the form from the bundle
    final topLevelFields = _topLevelFields;

    return ReorderableListView.builder(
      shrinkWrap: true,
      primary: false,
      physics: const NeverScrollableScrollPhysics(),
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
            form.relatedFields[i].definition = form.relatedFields[i].definition
                .copyWith(order: i);
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
    final isProduct =
        field.definition.type == FormMetadata.fieldTypeTicket ||
        field.definition.type == FormMetadata.fieldTypeProductType;
    final isSelected =
        _selectedIdentity == _identity(field) ||
        widget.expandProducts && isProduct;
    // The ticket flag also disables ticket issuance for application-only forms.
    // Its container and product choices remain active in that mode.
    final effectiveOpacity =
        field.definition.type != FormMetadata.fieldTypeTicket &&
            (field.definition.isHidden ?? false)
        ? kHiddenOpacity
        : 1.0;

    return GestureDetector(
      key: field.definition.id != null
          ? ValueKey(field.definition.id)
          : ObjectKey(field),
      onTap: () {
        if (!isSelected) {
          setState(() {
            _selectedIdentity = _identity(field);
          });
          _publishNavigation();
        }
      },
      child: Opacity(
        key: _anchors.putIfAbsent(_identity(field), () => GlobalKey()),
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
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (widget.expandProducts && isProduct) ...[
                  Text(
                    FormStrings.productsAndPrices,
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                  const SizedBox(height: 12),
                ],
                if (isSelected)
                  _buildFieldItemSelected(field, displayList, index)
                else
                  _buildFieldItemNonSelected(field),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _selectionOptionsError() => Padding(
    padding: const EdgeInsets.only(top: 8),
    child: Semantics(
      liveRegion: true,
      child: Text(
        FormStrings.selectionOptionsRequired,
        style: TextStyle(color: Theme.of(context).colorScheme.error),
      ),
    ),
  );

  Widget _buildFieldItemNonSelected(FormFieldDraft field) {
    final icon = FormHelper.fieldTypeIcons[field.definition.type];
    final bool hidden =
        field.definition.type != FormMetadata.fieldTypeTicket &&
        (field.definition.isHidden ?? false);
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
      if (!form.canDeleteField(field)) return;
      _refresh(() {
        displayList.remove(field);
        form.removeField(field);
        if (_selectedIdentity == _identity(field)) _selectedIdentity = null;
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
              hintText: FormHelper.fieldTypeToLocale(
                field.definition.type ?? '',
              ),
              contentPadding: const EdgeInsets.symmetric(vertical: 8),
            ),
            initialValue: field.definition.title,
            onChanged: (value) {
              field.definition = field.definition.copyWith(title: value);
              _publishNavigation();
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
                      field.definition = field.definition.copyWith(
                        description: newDescription,
                      );
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
                            FormHelper.fieldTypeIcons[field.definition.type],
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              FormHelper.fieldTypeToLocale(
                                field.definition.type!,
                              ),
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
                        field.definition = field.definition.copyWith(
                          data: null,
                        );
                        field.options.clear();
                      }
                      field.definition = field.definition.copyWith(
                        type: newType,
                      );
                      if ((field.definition.title?.isEmpty ?? true)) {
                        field.definition = field.definition.copyWith(
                          title: FormHelper.fieldTypeToLocale(newType),
                        );
                      }
                      if (FormMetadata.isAlwaysRequired(newType)) {
                        field.definition = field.definition.copyWith(
                          isRequired: true,
                        );
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
                    value:
                        FormMetadata.isAlwaysRequired(
                          field.definition.type ?? '',
                        ) ||
                        (field.definition.isRequired ?? false),
                    onChanged:
                        FormMetadata.isAlwaysRequired(
                          field.definition.type ?? '',
                        )
                        ? null
                        : (value) => _refresh(
                            () => field.definition = field.definition.copyWith(
                              isRequired: value,
                            ),
                          ),
                  ),
                ],
              ),
              if (!isTicket)
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
                          (field.definition.type ==
                                  FormMetadata.fieldTypeEmail ||
                              isTicket)
                          ? null
                          : (value) => _refresh(
                              () => field.definition = field.definition
                                  .copyWith(isHidden: !value),
                            ),
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
                          field.definition.description,
                        )) {
                          field.definition = field.definition.copyWith(
                            description: defaultDescription,
                          );
                        }
                      });
                    } else if (value == "delete_field") {
                      deleteField();
                    } else if (value == "show_deposit_description") {
                      _refresh(() {
                        field.definition = field.definition.copyWith(
                          data: field.definition.data ?? {},
                        );
                        var current =
                            field.definition.data![TicketHolder
                                .metaShowDepositDescription] ??
                            true;
                        field.definition = field.definition.copyWith(
                          data: {
                            ...?field.definition.data,
                            TicketHolder.metaShowDepositDescription: !current,
                          },
                        );
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
                          FeatureConstants.deposit,
                        )) {
                      bool showDeposit =
                          field.definition.data?[TicketHolder
                              .metaShowDepositDescription] ??
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
                          enabled: form.canDeleteField(field),
                          child: Tooltip(
                            message: form.canDeleteField(field)
                                ? CommonStrings.delete
                                : FormStrings.deletionReason(
                                    form.deletionBlockedReasonFor(field),
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
                    tooltip: form.canDeleteField(field)
                        ? CommonStrings.delete
                        : FormStrings.deletionReason(
                            form.deletionBlockedReasonFor(field),
                          ),
                    icon: const Icon(Icons.delete),
                    onPressed: form.canDeleteField(field) ? deleteField : null,
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
                style: Theme.of(context).textTheme.bodyLarge
                    ?.copyWith(color: Theme.of(context).hintColor),
              ),
            ),
          );
        } else {
          return Text(
            FormStrings.answerText,
            style: Theme.of(context).textTheme.bodyLarge
                ?.copyWith(color: Colors.grey),
          );
        }
    }
  }

  List<String> get _availableFieldTypes {
    final existingTypes = widget.bundle.form.relatedFields
        .map((f) => f.definition.type)
        .toList();
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
