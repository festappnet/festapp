import 'form_editor_toolbar.dart';
import 'form_editor_outline.dart';
import '../widgets_editor/form_fields_navigation_controller.dart';
import '../widgets_editor/form_editor_scroll.dart';
import 'form_unavailable_content_editor.dart';
import '../sale_opening_strings.dart';

import 'package:fstapp/data_services/authorization_capabilities.dart';

import '../waitlist_strings.dart';
import 'form_capacity_settings.dart';

import 'package:fstapp/components/forms/models/form_presentation.dart';
import 'package:fstapp/services/time_helper.dart';
import 'package:festapp_core/forms.dart';
import 'package:fstapp/widgets/app_dialog.dart';

import 'dart:async';

import 'package:fstapp/components/_shared/editor_action_bar.dart';
import 'package:fstapp/services/exception_handler.dart';
import 'package:fstapp/components/forms/form_html_content.dart';
import 'package:material_ui/material_ui.dart';
import 'package:fstapp/components/forms/models/form_editor_draft.dart';
import 'package:fstapp/router_service.dart';
import 'package:fstapp/components/forms/models/form_field_draft.dart';
import 'package:fstapp/data_services/rights_service.dart';
import 'package:fstapp/components/forms/db_forms.dart';
import 'package:fstapp/components/forms/views/form_page.dart';
import 'package:fstapp/components/forms/widgets_view/form_helper.dart';
import 'package:fstapp/services/toast_helper.dart';
import 'package:fstapp/styles/styles_config.dart';
import 'package:fstapp/theme_config.dart';
import 'package:fstapp/components/html/rich_html_editor_controller.dart';
import 'package:fstapp/components/html/editable_html_field.dart';
import 'package:easy_localization/easy_localization.dart';

import '../form_strings.dart';
import 'package:fstapp/components/_shared/common_strings.dart';
import '../widgets_editor/form_fields_generator.dart';
import 'package:fstapp/components/html/html_embedded_block.dart';

const double kHiddenOpacity = 0.5;

class FormEditorContent extends StatefulWidget {
  final String formLink;
  final Future<FormEditBundle?> Function(String)? loadBundle;
  final VoidCallback? onDataUpdated;
  final FormEditBundle? prototypeBundle;
  final ValueChanged<FormEditBundle>? onPrototypeSave;
  final ValueChanged<FormEditBundle>? onPrototypeHydrated;
  final bool embedded;
  const FormEditorContent({
    super.key,
    required this.formLink,
    this.onDataUpdated,
    this.loadBundle,
  }) : prototypeBundle = null,
       onPrototypeSave = null,
       onPrototypeHydrated = null,
       embedded = false;

  const FormEditorContent.prototype({
    super.key,
    required FormEditBundle bundle,
    required this.onPrototypeSave,
    this.onPrototypeHydrated,
    this.embedded = false,
  })  : loadBundle = null,
        formLink = '',
        onDataUpdated = null,
        prototypeBundle = bundle;

  @override
  _FormEditorContentState createState() => _FormEditorContentState();
}

class _FormEditorContentState extends State<FormEditorContent>
    with TickerProviderStateMixin {
  final _htmlSave = HtmlSaveCoordinator();
  final _snapshot = EditorSnapshot();
  final _draftRevision = ValueNotifier<int>(0);
  bool get _hasChanges =>
      _canEdit &&
      _bundle != null &&
      (_snapshot.differs(_bundle!.form.toEditedJson()) ||
          _htmlSave.hasActiveDraft);
  void _acceptRenderedDraft(FormEditBundle bundle) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !identical(_bundle, bundle)) return;
      _snapshot.accept(bundle.form.toEditedJson());
      _draftChanged(hydrated: true);
    });
  }

  void _draftChanged({bool hydrated = false}) => scheduleMicrotask(() {
    if (!mounted) return;
    _draftRevision.value++;
    if (widget.embedded && _bundle != null) {
      (hydrated
              ? widget.onPrototypeHydrated ?? widget.onPrototypeSave
              : widget.onPrototypeSave)
          ?.call(_bundle!);
    }
  });
  @override
  Widget build(BuildContext context) => HtmlEditingScope(
    coordinator: _htmlSave,
    child: _buildHtmlParent(context),
  );

  FormEditBundle? _bundle;
  bool _loadFailed = false;
  String? _formLink;
  final ScrollController _scrollController = ScrollController();
  final _fieldNavigation = FormFieldsNavigationController();
  final _selectedSection = ValueNotifier<String?>(null);
  GlobalKey _availabilityAnchor = GlobalKey();
  GlobalKey _introductionAnchor = GlobalKey();
  FormEditBundle? _anchorBundle;
  bool _prototypeSaved = false;
  bool get _prototype => widget.prototypeBundle != null;
  bool get _canEdit =>
      _prototype ||
      RightsService.hasCapability(AuthorizationCapabilities.formsWrite);
  bool get _canSeeReservations =>
      !_prototype && RightsService.canSeeReservations();

  @override
  void initState() {
    super.initState();
    _bundle = widget.prototypeBundle;
    if (_bundle != null) {
      _snapshot.accept(_bundle!.form.toEditedJson());
      _acceptRenderedDraft(_bundle!);
    }
  }

  @override
  void dispose() {
    _fieldNavigation.dispose();
    _selectedSection.dispose();
    _draftRevision.dispose();
    _htmlSave.dispose();
    if (_prototype && !widget.embedded && !_prototypeSaved && _bundle != null) {
      widget.onPrototypeSave?.call(_bundle!);
    }
    _scrollController.dispose();
    super.dispose();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_prototype) return;
    final newFormLink = widget.formLink;
    if (newFormLink != _formLink) {
      _formLink = newFormLink;
      loadData();
    }
  }

  Future<void> loadData() async {
    if (_formLink == null) return;
    final link = _formLink!;
    setState(() => _loadFailed = false);
    final bundle = await ExceptionHandler.guard<FormEditBundle?>(
      context,
      futureFunction: () => (widget.loadBundle ?? DbForms.getFormForEdit)(link),
    );
    if (!mounted || link != _formLink) return;
    setState(() {
      _bundle = bundle;
      _loadFailed = bundle == null;
      if (bundle != null) {
        _snapshot.accept(bundle.form.toEditedJson());
        _acceptRenderedDraft(bundle);
      }
    });
  }

  Future<void> saveChanges() async {
    await ExceptionHandler.guardVoid(
      context,
      futureFunction: () =>
          _htmlSave.save(() => _performHtmlSave(), context: context),
    );
  }

  Future<void> _performHtmlSave() async {
    // UPDATED: Check for bundle and use bundle.form
    if (_bundle == null) return;
    final form = _bundle!.form;
    if (form.relatedFields.any((field) => field.hasInvalidSelectionOptions)) {
      ToastHelper.Show(
        context,
        FormStrings.selectionOptionsRequired,
        severity: ToastSeverity.NotOk,
      );
      return;
    }

    if (form.definition.startTime != null && form.definition.endTime != null) {
      if (form.definition.endTime!.isBefore(form.definition.startTime!)) {
        ToastHelper.Show(
          context,
          FormStrings.errorEndTimeBeforeStartTime,
          severity: ToastSeverity.NotOk,
        );
        return;
      }
    }

    form.relatedFields.sort(
      (a, b) => (a.definition.order ?? 0).compareTo(b.definition.order ?? 0),
    );
    for (int i = 0; i < form.relatedFields.length; i++) {
      form.relatedFields[i].definition = form.relatedFields[i].definition
          .copyWith(order: i);
    }

    for (final field in form.relatedFields) {
      if (field.definition.isTicketField == true &&
          field.definition.type == FormMetadata.fieldTypeProductType &&
          field.definition.productType != null &&
          field.definition.productType!.products != null) {
        final products = [...field.definition.productType!.products!]
          ..sort((a, b) => (a.order ?? 0).compareTo(b.order ?? 0));
        field.definition = field.definition.copyWith(
          productType: field.definition.productType!.copyWith(
            products: [
              for (var index = 0; index < products.length; index++)
                products[index].copyWith(order: index),
            ],
          ),
        );
      }
    }

    try {
      if (_prototype) {
        _prototypeSaved = true;
        widget.onPrototypeSave?.call(_bundle!);
        if (mounted && !widget.embedded) Navigator.of(context).pop();
        return;
      }
      await prepareFormHtml(form, _htmlSave);
      final saved = await DbForms.updateForm(form);
      _htmlSave.markSaved();
      if (!mounted) return;
      ToastHelper.Show(
        context,
        "${CommonStrings.saved}: ${form.definition.link}",
        severity: ToastSeverity.Ok,
      );
      setState(() {
        _bundle = _bundle!.afterSave(saved);
        _snapshot.accept(saved.toEditedJson());
        _acceptRenderedDraft(_bundle!);
      });
      widget.onDataUpdated?.call();
    } catch (e) {
      if (!mounted) return;
      String? capacityError;
      for (final code in [
        'CAPACITY_BELOW_COMMITTED',
        'WAITLIST_HAS_ACTIVE_ENTRIES',
        'BLUEPRINT_CONFLICT',
      ]) {
        if (e.toString().contains(code)) {
          capacityError = code;
          break;
        }
      }
      ToastHelper.Show(
        context,
        capacityError == null
            ? FormStrings.saveError(e)
            : WaitlistStrings.text(capacityError),
        severity: ToastSeverity.NotOk,
      );
    }
  }

  Future<void> cancelEdit() async {
    await loadData();
    if (mounted) _htmlSave.markSaved();
  }

  List<String> get _availableFieldTypes {
    final existingTypes =
        _bundle?.form.relatedFields.map((f) => f.definition.type).toList() ??
            [];
    return FormHelper.fieldTypeIcons.keys.where((type) {
      if ([
        FormMetadata.fieldTypeText,
        FormMetadata.fieldTypeSelectOne,
        FormMetadata.fieldTypeSelectMany,
      ].contains(type)) {
        return true;
      }
      return !existingTypes.contains(type);
    }).toList();
  }

  Widget _buildFormOpenToggleAndOffTextEditor() {
    if (_bundle == null) return const SizedBox.shrink();
    final form = _bundle!.form;
    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(
        side: BorderSide(color: Colors.grey.withOpacity(0.3)),
        borderRadius: BorderRadius.circular(8),
      ),
      margin: const EdgeInsets.symmetric(vertical: 8.0),
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(FormStrings.availability,
                          style: Theme.of(context)
                              .textTheme
                              .titleMedium
                              ?.copyWith(fontWeight: FontWeight.bold)),
                      _buildAvailabilityStatusBanner(form),
                      /*
                        (form.isOpen ?? true) ? FormStrings.formOpenMessage : FormStrings.formClosedMessage,
                        style: TextStyle(
                            color: (form.isOpen ?? true)
                                ? Theme.of(context).primaryColor
                                : ThemeConfig.redColor(context),
                            fontWeight: FontWeight.bold
                        ),
                        */
                    ],
                  ),
                ),
                Switch(
                  value: _prototype ? false : form.definition.isOpen ?? true,
                  onChanged: _canEdit && !_prototype
                      ? (val) => setState(() {
                            form.definition =
                                form.definition.copyWith(isOpen: val);
                          })
                      : null,
                ),
              ],
            ),
            const SizedBox(height: 16),
            if (_canSeeReservations) ...[
              FormCapacitySettings(
                form: form,
                canEdit: _canEdit,
                onChanged: () {
                  setState(() {});
                  _draftChanged();
                },
              ),
              const Divider(height: 24),
              ExpansionTile(
                tilePadding: EdgeInsets.zero,
                childrenPadding: EdgeInsets.zero,
                title: Text(FormStrings.scheduleAndLimits,
                    style: const TextStyle(fontWeight: FontWeight.w600)),
                subtitle: Text(FormStrings.autoOpenHelp,
                    style: Theme.of(context).textTheme.bodySmall),
                initiallyExpanded: false,
                shape: const Border(), // Remove default borders
                children: [
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      Expanded(
                        child: _buildDateTimeInput(FormStrings.labelStartTime,
                            form.definition.startTime, (date) {
                          setState(() {
                            form.definition = form.definition.withStartTimeUtc(
                                (date)?.toUtcFromOccasionTime());
                            if (date == null) {
                              form.definition =
                                  form.definition.withEnableCountdown(false);
                            } else {
                              if (form.definition.endTime == null ||
                                  form.definition.endTime!.isBefore(date)) {
                                form.definition = form.definition
                                    .withEndTimeUtc(date
                                        .add(const Duration(hours: 1))
                                        .toUtcFromOccasionTime());
                              }
                            }
                          });
                        }, isStart: true, enabled: _canEdit),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: _buildDateTimeInput(
                            FormStrings.labelEndTime, form.definition.endTime,
                            (date) {
                          // Validation Logic: Prevent setting end time before start time
                          // Note: UI picker is now also restricted, but this double check is safe.
                          if (date != null &&
                              form.definition.startTime != null &&
                              date.isBefore(form.definition.startTime!)) {
                            ToastHelper.Show(context,
                                FormStrings.errorEndTimeBeforeStartTime,
                                severity: ToastSeverity.NotOk);
                            return;
                          }
                          setState(() => form.definition = form.definition
                              .withEndTimeUtc((date)?.toUtcFromOccasionTime()));
                        },
                            isEnd: true,
                            minDate: form.definition.startTime,
                            enabled: _canEdit),
                      ),
                    ],
                  )],
                      ),
                  const Divider(height: 24),
              FormUnavailableContentEditor(
                form: form,
                coordinator: _htmlSave,
                canEdit: _canEdit && !_prototype,
                onChanged: _draftChanged,
                closedContent: _buildHtmlFieldPreview(
                  FormStrings.labelMessageContent,
                  form.definition.headerOff,
                  (val) => setState(() => form.definition =
                      form.definition.copyWith(headerOff: val)),
                  helpText: FormStrings.helperClosedMessage,
                  defaultText: FormStrings.reservationUnavailableMessage,
                  showLabel: false,
                  enabled: _canEdit,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildDateTimeInput(
      String label, DateTime? value, Function(DateTime?) onChanged,
      {bool isStart = false,
      bool isEnd = false,
      DateTime? minDate,
      bool enabled = true}) {
    /*
    Color? statusColor;
    String statusText = "";
    if (value != null) {
      final now = DateTime.now();
      if (isStart) {
        if (value.isAfter(now)) {
           statusColor = Colors.grey; statusText = "Pending";
        } else {
           statusColor = Theme.of(context).primaryColor; statusText = "Active";
        }
      } else if (isEnd) {
         if (value.isBefore(now)) {
            statusColor = Colors.grey; statusText = "Ended";
         } else {
            statusColor = Theme.of(context).primaryColor; statusText = "Active";
         }
      }
    }
    */

    return InkWell(
      onTap: !enabled
          ? null
          : () async {
              final initialDate = value ?? DateTime.now();
              final firstDate = minDate ?? DateTime(2000);

              // Ensure initialDate is valid (must be >= firstDate)
              final effectiveInitialDate =
                  initialDate.isBefore(firstDate) ? firstDate : initialDate;

              final date = await showDatePicker(
                context: context,
                initialDate: effectiveInitialDate,
                firstDate: firstDate,
                lastDate: DateTime(2100),
              );
              if (date != null) {
                final time = await showTimePicker(
                  context: context,
                  initialTime: TimeOfDay.fromDateTime(value ?? DateTime.now()),
                );
                if (time != null) {
                  onChanged(DateTime(
                      date.year, date.month, date.day, time.hour, time.minute));
                }
              }
            },
      child: InputDecorator(
        decoration: InputDecoration(
          labelText: label,
          border: const OutlineInputBorder(),
          contentPadding:
              const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          suffixIcon: value != null && enabled
              ? IconButton(
                  icon: const Icon(Icons.clear, size: 18),
                  onPressed: () => onChanged(null))
              : const Icon(Icons.calendar_today, size: 18),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(
                value != null
                    ? DateFormat.yMd().add_jm().format(value)
                    : FormStrings.notSet,
                style: const TextStyle(fontSize: 14)),
            /*
            if (statusText.isNotEmpty)
               Padding(
                 padding: const EdgeInsets.only(top: 2.0),
                 child: Text(statusText, style: TextStyle(color: statusColor, fontSize: 10, fontWeight: FontWeight.bold)),
               )
            */
          ],
        ),
      ),
    );
  }

  Widget _buildAvailabilityStatusBanner(FormEditorDraft form) {
    String text;
    Color color;
    final now = DateTime.now();

    if (!(form.definition.isOpen ?? true)) {
      text = FormStrings.formClosedMessage;
      color = ThemeConfig.redColor(context);
    } else if (form.definition.startTime != null &&
        now.isBefore(form.definition.startTime!)) {
      text = FormStrings.scheduledWithTime(
          DateFormat.Md().add_jm().format(form.definition.startTime!));
      color = ThemeConfig.redColor(context);
    } else if (form.definition.endTime != null &&
        now.isAfter(form.definition.endTime!)) {
      text = FormStrings.endedWithTime(
          DateFormat.Md().add_jm().format(form.definition.endTime!));
      color = ThemeConfig.redColor(context);
    } else if (!_prototype && form.definition.isWaitlist) {
      text = WaitlistStrings.formOpenWaitlistMessage;
      color = ThemeConfig.warningColor(context);
    } else {
      text = FormStrings.formOpenMessage;
      color = Theme.of(context).primaryColor;
    }

    return Text(
      text,
      style: TextStyle(color: color, fontWeight: FontWeight.bold),
    );
  }

  Widget _buildHtmlFieldPreview(
      String label, String? content, ValueChanged<String> onChanged,
      {List<HtmlEmbeddedBlock> embeddedBlocks = const [],
      String? defaultText,
      String? helpText,
      bool showLabel = true,
      bool minimal = false,
      double? fontSize,
      bool enabled = true}) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (showLabel || helpText != null)
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (showLabel)
                      Text(label,
                          style: const TextStyle(fontWeight: FontWeight.bold)),
                    if (helpText != null)
                      Text(helpText,
                          style: Theme.of(context).textTheme.bodySmall),
                  ],
                ),
              ),
            ],
          ),
        if (showLabel || helpText != null) const SizedBox(height: 8),
        Container(
          width: double.infinity,
          decoration: minimal
              ? null
              : BoxDecoration(
                  color: Theme.of(context).brightness == Brightness.dark
                      ? Colors.grey.withOpacity(0.2)
                      : Colors.grey.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(4),
                  border: Border.all(
                      color: Theme.of(context).brightness == Brightness.dark
                          ? Colors.white24
                          : Colors.grey.withOpacity(0.3)),
                ),
          child: Padding(
            padding: EdgeInsets.all(minimal ? 4 : 12),
            child: EditableHtmlField(
              html: content ?? '',
              embeddedBlocks: embeddedBlocks,
              placeholder: defaultText ?? FormStrings.notSet,
              enabled: enabled && !_prototype,
              fontSize: fontSize ?? 13,
              coordinator: _htmlSave,
              owner:
                  HtmlMediaOwner.occasion(_bundle!.form.definition.occasionId),
              onChanged: onChanged,
            ),
          ),
        ),
      ],
    );
  }

  Future<void> _openPublicForm({bool preview = false}) async {
    if (_formLink == null) return;
    if (_hasChanges) {
      final choice = await showDialog<String>(
        context: context,
        builder: (dialogContext) => AppAlertDialog(
          title: Text(SaleOpeningStrings.text('unsavedChanges')),
          content: Text(SaleOpeningStrings.text('viewSavedHint')),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: Text(CommonStrings.keepEditing),
            ),
            TextButton(
              onPressed: () => Navigator.pop(dialogContext, 'stored'),
              child: Text(SaleOpeningStrings.text('showSavedAction')),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(dialogContext, 'save'),
              child: Text(SaleOpeningStrings.text('saveAndViewAction')),
            ),
          ],
        ),
      );
      if (choice == null || !mounted) return;
      if (choice == 'save') {
        await saveChanges();
        if (!mounted || _hasChanges) return;
      }
    }
    if (!mounted) return;
    await RouterService.navigate(
      context,
      '${FormPage.ROUTE}/$_formLink${preview ? '?preview=true' : ''}',
    );
  }

  void _addNewField() async {
    if (_bundle == null) return;

    final availableTypes = _availableFieldTypes;
    final personalInfoTypes = FormMetadata.personalInfoFields
        .where((type) => availableTypes.contains(type))
        .toList();
    final otherTypes = availableTypes
        .where((type) => !FormMetadata.personalInfoFields.contains(type))
        .toList();

    String? finalSelectedType;
    bool isWideScreen = MediaQuery.of(context).size.width > 600;

    finalSelectedType = await showDialog<String>(
      context: context,
      builder: (BuildContext dialogContext) {
        List<Widget> resolvedItemsForDialog = [];
        if (personalInfoTypes.isNotEmpty) {
          resolvedItemsForDialog.add(PopupMenuButton<String>(
            tooltip: FormStrings.personalInfo,
            offset: isWideScreen ? const Offset(160, 0) : const Offset(20, 0),
            shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(8.0)),
            onSelected: (String type) {
              Navigator.of(dialogContext).pop(type);
            },
            itemBuilder: (BuildContext popupContext) {
              return personalInfoTypes.map((type) {
                return PopupMenuItem<String>(
                  value: type,
                  child: Row(
                    children: [
                      Icon(
                          FormHelper.fieldTypeIcons[type] ??
                              Icons.circle_outlined,
                          size: 20,
                          color: Theme.of(context).textTheme.bodyLarge?.color),
                      const SizedBox(width: 12),
                      Text(FormHelper.fieldTypeToLocale(type)),
                    ],
                  ),
                );
              }).toList();
            },
            child: ListTile(
              leading: Icon(Icons.person_search_outlined,
                  size: 20,
                  color: Theme.of(context).textTheme.bodyLarge?.color),
              title: Text(FormStrings.personalInfo),
              trailing: Icon(Icons.chevron_right,
                  color: Theme.of(context).textTheme.bodyLarge?.color),
              dense: true,
            ),
          ));
          resolvedItemsForDialog.add(const Divider(height: 1, thickness: 0.5));
        }

        resolvedItemsForDialog.addAll(otherTypes.map((type) {
          return ListTile(
            leading: Icon(
                FormHelper.fieldTypeIcons[type] ?? Icons.circle_outlined,
                size: 20,
                color: Theme.of(context).textTheme.bodyLarge?.color),
            title: Text(FormHelper.fieldTypeToLocale(type)),
            dense: true,
            onTap: () {
              Navigator.of(dialogContext).pop(type);
            },
          );
        }).toList());

        if (resolvedItemsForDialog.isEmpty) {
          resolvedItemsForDialog.add(Center(
            child: Padding(
              padding: const EdgeInsets.all(16.0),
              child: Text(FormStrings.noFieldsAvailable),
            ),
          ));
        }

        return AppAlertDialog(
          title: Text(FormStrings.addFieldTitle),
          contentPadding: const EdgeInsets.symmetric(vertical: 8.0),
          content: SizedBox(
            width: 280,
            child: ListView(
              shrinkWrap: true,
              children: resolvedItemsForDialog,
            ),
          ),
        );
      },
    );

    if (finalSelectedType != null) {
      _addFieldOfType(finalSelectedType);
    }
  }

  void _addFieldOfType(String type) {
    if (!mounted || _bundle == null) return;
    final bundle = _bundle!;
    final form = bundle.form;
    final newField = FormFieldDraft(
      type: type,
      order: form.relatedFields.length,
      isRequired: FormMetadata.isAlwaysRequired(type),
      isHidden: false,
      isTicketField: false,
    );

    setState(() {
      form.relatedFields = List.from(form.relatedFields)..add(newField);
    });
    _draftChanged();

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted ||
          !identical(_bundle, bundle) ||
          !bundle.form.relatedFields.contains(newField))
        return;
      _selectedSection.value = null;
      _fieldNavigation.revealField(newField);
    });
  }

  void _revealSection(String section, GlobalKey anchor) {
    _fieldNavigation.clearSelection();
    _selectedSection.value = section;
    final target = anchor.currentContext;
    if (target != null) {
      revealFormEditorTarget(
        target,
        controller: _scrollController,
        alignment: 0,
      );
    }
  }

  ButtonStyle _addFieldButtonStyle() => TextButton.styleFrom(
    minimumSize: const Size(180, 52),
    padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
    textStyle: Theme.of(context).textTheme.titleMedium
        ?.copyWith(fontWeight: FontWeight.w600),
    iconSize: 26,
    visualDensity: VisualDensity.standard,
    tapTargetSize: MaterialTapTargetSize.padded,
  );

  Widget _buildHtmlParent(BuildContext context) {
    if (!identical(_anchorBundle, _bundle)) {
      _anchorBundle = _bundle;
      _availabilityAnchor = GlobalKey();
      _introductionAnchor = GlobalKey();
    }
    if (_bundle == null) {
      return Scaffold(
        body: Center(
          child: _loadFailed
              ? Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(CommonStrings.unexpectedError),
                    const SizedBox(height: 12),
                    FilledButton(
                      onPressed: loadData,
                      child: Text(CommonStrings.retry),
                    ),
                  ],
                )
              : const CircularProgressIndicator(),
        ),
      );
    }

    if (widget.embedded) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (_canEdit)
            Text(
              FormStrings.dragToReorder,
              style: Theme.of(context).textTheme.bodySmall,
            ),
          const SizedBox(height: 16),
          Form(
            onChanged: _draftChanged,
            child: FormFieldsGenerator(
              key: ObjectKey(_bundle),
              bundle: _bundle!,
              navigationController: _fieldNavigation,
              expandProducts: true,
              editingEnabled: _canEdit,
              onChanged: _draftChanged,
            ),
          ),
          const SizedBox(height: 16),
          Align(
            alignment: Alignment.centerRight,
            child: FilledButton.icon(
              style: _addFieldButtonStyle(),
              onPressed: _canEdit ? _addNewField : null,
              icon: const Icon(Icons.add),
              label: Text(FormStrings.addFieldTitle),
            ),
          ),
        ],
      );
    }

    return Scaffold(
      body: LayoutBuilder(
        builder: (context, constraints) {
          // The content remains at the same position in one tree at every width.
          // Hiding the outline must never remount rich text or field drafts.
          final textScale = MediaQuery.textScalerOf(context).scale(14) / 14;
          final showOutline =
              !_prototype &&
              constraints.maxWidth >= 1100 &&
              constraints.maxWidth >=
                  216 * textScale + 24 + StylesConfig.formMaxWidth + 24;
          return Align(
            key: ObjectKey(_bundle),
            alignment: Alignment.topCenter,
            child: ConstrainedBox(
              constraints: BoxConstraints(
                maxWidth: showOutline
                    ? 216 + 24 + StylesConfig.formMaxWidth
                    : StylesConfig.formMaxWidth,
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  if (!_prototype)
                    Padding(
                      padding: const EdgeInsets.fromLTRB(6, 12, 6, 8),
                      child: FormEditorToolbar(
                        onPreview: () => _openPublicForm(preview: true),
                        onPublicPage: () => _openPublicForm(),
                      ),
                    ),
                  Expanded(
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        SizedBox(
                          width: showOutline ? 216 : 0,
                          child: showOutline
                              ? AnimatedBuilder(
                                  animation: Listenable.merge([
                                    _fieldNavigation,
                                    _selectedSection,
                                  ]),
                                  builder: (context, _) => FormEditorOutline(
                                    key: const ValueKey('form-editor-outline'),
                                    fields: _fieldNavigation.fields,
                                    selectedIdentity:
                                        _fieldNavigation.selectedIdentity,
                                    selectedSection: _selectedSection.value,
                                    onAvailability: () => _revealSection(
                                      'availability',
                                      _availabilityAnchor,
                                    ),
                                    onIntroduction: () => _revealSection(
                                      'introduction',
                                      _introductionAnchor,
                                    ),
                                    onField: (field) {
                                      _selectedSection.value = null;
                                      _fieldNavigation.revealField(field);
                                    },
                                  ),
                                )
                              : null,
                        ),
                        SizedBox(width: showOutline ? 24 : 0),
                        Expanded(
                          child: SingleChildScrollView(
                            controller: _scrollController,
                            child: Padding(
                              padding: const EdgeInsets.all(6),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.stretch,
                                children: [
                                  KeyedSubtree(
                                    key: _availabilityAnchor,
                                    child:
                                        _buildFormOpenToggleAndOffTextEditor(),
                                  ),
                                  const Divider(
                                    thickness: 1,
                                    color: Colors.grey,
                                  ),
                                  Padding(
                                    key: _introductionAnchor,
                                    padding: const EdgeInsets.only(
                                      top: 16,
                                      bottom: 8,
                                    ),
                                    child: Text(
                                      FormStrings.formIntroduction,
                                      style: Theme.of(context)
                                          .textTheme
                                          .titleMedium,
                                    ),
                                  ),
                                  EditableHtmlField(
                                    key: const ValueKey('form-header'),
                                    html: _bundle!.form.definition.header,
                                    enabled: _canEdit && !_prototype,
                                    coordinator: _htmlSave,
                                    owner: HtmlMediaOwner.occasion(
                                      _bundle!.form.definition.occasionId,
                                    ),
                                    onChanged: (html) => setState(
                                      () => _bundle!.form.definition = _bundle!
                                          .form
                                          .definition
                                          .copyWith(header: html),
                                    ),
                                  ),
                                  const SizedBox(height: 24),
                                  if (_canEdit) ...[
                                    Align(
                                      alignment: Alignment.centerLeft,
                                      child: TextButton.icon(
                                        style: _addFieldButtonStyle(),
                                        key: const ValueKey(
                                          'add-form-field-top',
                                        ),
                                        onPressed: _addNewField,
                                        icon: const Icon(Icons.add),
                                        label: Text(FormStrings.addFieldTitle),
                                      ),
                                    ),
                                    Text(
                                      FormStrings.dragToReorder,
                                      style: Theme.of(context)
                                          .textTheme
                                          .bodySmall,
                                    ),
                                    const SizedBox(height: 16),
                                  ],
                                  Form(
                                    onChanged: _draftChanged,
                                    child: FormFieldsGenerator(
                                      key: ObjectKey(_bundle),
                                      bundle: _bundle!,
                                      navigationController: _fieldNavigation,
                                      revealScrollController: _scrollController,
                                      editingEnabled: _canEdit,
                                      onChanged: _draftChanged,
                                    ),
                                  ),
                                  if (_canEdit)
                                    Align(
                                      alignment: Alignment.centerLeft,
                                      child: TextButton.icon(
                                        style: _addFieldButtonStyle(),
                                        key: const ValueKey(
                                          'add-form-field-bottom',
                                        ),
                                        onPressed: _addNewField,
                                        icon: const Icon(Icons.add),
                                        label: Text(FormStrings.addFieldTitle),
                                      ),
                                    ),
                                  const SizedBox(height: 24),
                                ],
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
      bottomNavigationBar: AnimatedBuilder(
        animation: Listenable.merge([_htmlSave, _draftRevision]),
        builder: (context, _) => _prototype
            ? BottomAppBar(
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    TextButton(
                      onPressed: () => Navigator.of(context).pop(),
                      child: Text(CommonStrings.back),
                    ),
                    FilledButton(
                      onPressed: _hasChanges ? saveChanges : null,
                      child: Text(CommonStrings.save),
                    ),
                  ],
                ),
              )
            : EditorActionBar(
                hasChanges: _hasChanges,
                enabled: _canEdit && _bundle != null,
                onSave: saveChanges,
                onDiscard: cancelEdit,
              ),
      ),
    );
  }
}
