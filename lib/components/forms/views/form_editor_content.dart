import 'package:fstapp/services/exception_handler.dart';
import 'package:fstapp/components/forms/form_html_content.dart';
import 'package:flutter/material.dart';
import 'package:fstapp/components/forms/models/form_model.dart';
import 'package:fstapp/router_service.dart';
import 'package:fstapp/components/forms/models/form_field_model.dart';
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

import 'package:fstapp/components/forms/widgets_view/countdown_widget.dart';

const double kHiddenOpacity = 0.5;

class FormEditorContent extends StatefulWidget {
  final String formLink;
  final VoidCallback? onDataUpdated;
  const FormEditorContent({
    super.key,
    required this.formLink,
    this.onDataUpdated,
  });

  @override
  _FormEditorContentState createState() => _FormEditorContentState();
}

class _FormEditorContentState extends State<FormEditorContent>
    with TickerProviderStateMixin {
  final _htmlSave = HtmlSaveCoordinator();
  @override
  Widget build(BuildContext context) => HtmlEditingScope(
    coordinator: _htmlSave,
    child: _buildHtmlParent(context),
  );

  FormEditBundle? _bundle;
  String? _formLink;
  final ScrollController _scrollController = ScrollController();
  @override
  void dispose() {
    _htmlSave.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final newFormLink = widget.formLink;
    if (newFormLink != _formLink) {
      _formLink = newFormLink;
      loadData();
    }
  }

  Future<void> loadData() async {
    if (_formLink == null) return;
    final bundle = await DbForms.getFormForEdit(_formLink!);
    if (mounted) {
      setState(() {
        _bundle = bundle;
      });
    }
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

    if (form.startTime != null && form.endTime != null) {
      if (form.endTime!.isBefore(form.startTime!)) {
        ToastHelper.Show(
          context,
          FormStrings.errorEndTimeBeforeStartTime,
          severity: ToastSeverity.NotOk,
        );
        return;
      }
    }

    form.relatedFields.sort((a, b) => (a.order ?? 0).compareTo(b.order ?? 0));
    for (int i = 0; i < form.relatedFields.length; i++) {
      form.relatedFields[i].order = i;
    }

    for (final field in form.relatedFields) {
      if (field.isTicketField == true &&
          field.type == FormHelper.fieldTypeProductType &&
          field.productType != null &&
          field.productType!.products != null) {
        field.productType!.products!.sort(
          (a, b) => (a.order ?? 0).compareTo(b.order ?? 0),
        );
        for (int i = 0; i < field.productType!.products!.length; i++) {
          field.productType!.products![i].order = i;
        }
      }
    }

    try {
      await prepareFormHtml(form, _htmlSave);
      await DbForms.updateForm(form);
      _htmlSave.markSaved();
      if (!mounted) return;
      ToastHelper.Show(
        context,
        "${CommonStrings.saved}: ${form.link}",
        severity: ToastSeverity.Ok,
      );
      await loadData();
      widget.onDataUpdated?.call();
    } catch (e) {
      if (!mounted) return;
      ToastHelper.Show(
        context,
        e.toString().replaceFirst("Exception: ", ""),
        severity: ToastSeverity.NotOk,
      );
    }
  }

  Future<void> cancelEdit() async {
    if (!await confirmHtmlDiscard(context, _htmlSave) || !mounted) return;
    Navigator.of(context).pop();
  }

  List<String> get _availableFieldTypes {
    final existingTypes =
        _bundle?.form.relatedFields.map((f) => f.type).toList() ?? [];
    return FormHelper.fieldTypeIcons.keys.where((type) {
      if ([
        FormHelper.fieldTypeText,
        FormHelper.fieldTypeSelectOne,
        FormHelper.fieldTypeSelectMany,
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
                      Text(
                        FormStrings.availability,
                        style: Theme.of(context).textTheme.titleMedium
                            ?.copyWith(fontWeight: FontWeight.bold),
                      ),
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
                  value: form.isOpen ?? true,
                  onChanged: RightsService.isOrderEditor()
                      ? (val) => setState(() {
                          form.isOpen = val;
                        })
                      : null,
                ),
              ],
            ),
            const SizedBox(height: 16),
            if (RightsService.canSeeReservations()) ...[
              ExpansionTile(
                tilePadding: EdgeInsets.zero,
                childrenPadding: EdgeInsets.zero,
                title: Text(
                  FormStrings.scheduleAndLimits,
                  style: const TextStyle(fontWeight: FontWeight.w600),
                ),
                subtitle: Text(
                  FormStrings.autoOpenHelp,
                  style: Theme.of(context).textTheme.bodySmall,
                ),
                initiallyExpanded: false,
                shape: const Border(), // Remove default borders
                children: [
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      Expanded(
                        child: _buildDateTimeInput(
                          FormStrings.labelStartTime,
                          form.startTime,
                          (date) {
                            setState(() {
                              form.startTime = date;
                              if (date == null) {
                                form.enableCountdown = false;
                              } else {
                                if (form.endTime == null ||
                                    form.endTime!.isBefore(date)) {
                                  form.endTime = date.add(
                                    const Duration(hours: 1),
                                  );
                                }
                              }
                            });
                          },
                          isStart: true,
                          enabled: RightsService.isOrderEditor(),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: _buildDateTimeInput(
                          FormStrings.labelEndTime,
                          form.endTime,
                          (date) {
                            // Validation Logic: Prevent setting end time before start time
                            // Note: UI picker is now also restricted, but this double check is safe.
                            if (date != null &&
                                form.startTime != null &&
                                date.isBefore(form.startTime!)) {
                              ToastHelper.Show(
                                context,
                                FormStrings.errorEndTimeBeforeStartTime,
                                severity: ToastSeverity.NotOk,
                              );
                              return;
                            }
                            setState(() => form.endTime = date);
                          },
                          isEnd: true,
                          minDate: form.startTime,
                          enabled: RightsService.isOrderEditor(),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    secondary: const Icon(Icons.timer_outlined),
                    title: Text(
                      FormStrings.labelCountdownTimer,
                      style: const TextStyle(fontWeight: FontWeight.w600),
                    ),
                    subtitle: Text(
                      form.startTime == null
                          ? FormStrings.requiresStartTime
                          : FormStrings.countdownDescription,
                      style: TextStyle(
                        color: form.startTime == null ? Colors.grey : null,
                        fontSize: 12,
                      ),
                    ),
                    value: form.enableCountdown,
                    onChanged:
                        form.startTime != null && RightsService.isOrderEditor()
                        ? (val) => setState(() => form.enableCountdown = val)
                        : null,
                  ),
                  if (form.enableCountdown && form.startTime != null) ...[
                    const SizedBox(height: 12),
                    Container(
                      decoration: BoxDecoration(
                        border: Border.all(color: Colors.grey.withOpacity(0.2)),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      padding: const EdgeInsets.only(bottom: 4),
                      child: Column(
                        children: [
                          _buildHtmlFieldPreview(
                            FormStrings.labelCountdownMessage,
                            form.countdownTitle,
                            (val) => setState(() => form.countdownTitle = val),
                            defaultText: FormStrings.registrationStart,
                            showLabel: false,
                            minimal: true,
                            fontSize: 20,
                            enabled: RightsService.isOrderEditor(),
                          ),
                          Transform.scale(
                            scale: 0.8,
                            child: CountdownWidget(
                              targetTime: form.startTime!,
                              onFinished: () {},
                              title: null,
                              compact: true,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ],
              ),
              const Divider(height: 24),
              ExpansionTile(
                tilePadding: EdgeInsets.zero,
                childrenPadding: EdgeInsets.zero,
                title: Text(
                  FormStrings.labelClosedMessage,
                  style: const TextStyle(fontWeight: FontWeight.w600),
                ),
                initiallyExpanded: false,
                shape: const Border(),
                children: [
                  _buildHtmlFieldPreview(
                    FormStrings.labelMessageContent,
                    form.headerOff,
                    (val) => setState(() => form.headerOff = val),
                    helpText: FormStrings.helperClosedMessage,
                    defaultText: FormStrings.reservationUnavailableMessage,
                    showLabel: false,
                    enabled: RightsService.isOrderEditor(),
                  ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildDateTimeInput(
    String label,
    DateTime? value,
    Function(DateTime?) onChanged, {
    bool isStart = false,
    bool isEnd = false,
    DateTime? minDate,
    bool enabled = true,
  }) {
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
              final effectiveInitialDate = initialDate.isBefore(firstDate)
                  ? firstDate
                  : initialDate;

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
                  onChanged(
                    DateTime(
                      date.year,
                      date.month,
                      date.day,
                      time.hour,
                      time.minute,
                    ),
                  );
                }
              }
            },
      child: InputDecorator(
        decoration: InputDecoration(
          labelText: label,
          border: const OutlineInputBorder(),
          contentPadding: const EdgeInsets.symmetric(
            horizontal: 12,
            vertical: 8,
          ),
          suffixIcon: value != null && enabled
              ? IconButton(
                  icon: const Icon(Icons.clear, size: 18),
                  onPressed: () => onChanged(null),
                )
              : const Icon(Icons.calendar_today, size: 18),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(
              value != null
                  ? DateFormat('dd.MM.yyyy HH:mm').format(value)
                  : FormStrings.notSet,
              style: const TextStyle(fontSize: 14),
            ),
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

  Widget _buildAvailabilityStatusBanner(FormModel form) {
    String text;
    Color color;
    final now = DateTime.now();

    if (!(form.isOpen ?? true)) {
      text = FormStrings.formClosedMessage;
      color = ThemeConfig.redColor(context);
    } else if (form.startTime != null && now.isBefore(form.startTime!)) {
      text = FormStrings.scheduledWithTime(
        DateFormat('dd.MM HH:mm').format(form.startTime!),
      );
      color = ThemeConfig.redColor(context);
    } else if (form.endTime != null && now.isAfter(form.endTime!)) {
      text = FormStrings.endedWithTime(
        DateFormat('dd.MM HH:mm').format(form.endTime!),
      );
      color = ThemeConfig.redColor(context);
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
    String label,
    String? content,
    ValueChanged<String> onChanged, {
    String? defaultText,
    String? helpText,
    bool showLabel = true,
    bool minimal = false,
    double? fontSize,
    bool enabled = true,
  }) {
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
                      Text(
                        label,
                        style: const TextStyle(fontWeight: FontWeight.bold),
                      ),
                    if (helpText != null)
                      Text(
                        helpText,
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
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
                        : Colors.grey.withOpacity(0.3),
                  ),
                ),
          child: Padding(
            padding: EdgeInsets.all(minimal ? 4 : 12),
            child: EditableHtmlField(
              html: content ?? '',
              placeholder: defaultText ?? FormStrings.notSet,
              enabled: enabled,
              fontSize: fontSize ?? 13,
              coordinator: _htmlSave,
              owner: HtmlMediaOwner.occasion(_bundle!.form.occasionId),
              onChanged: onChanged,
            ),
          ),
        ),
      ],
    );
  }

  void _addNewField() async {
    if (_bundle == null) return;

    final availableTypes = _availableFieldTypes;
    final personalInfoTypes = FormHelper.personalInfoFields
        .where((type) => availableTypes.contains(type))
        .toList();
    final otherTypes = availableTypes
        .where((type) => !FormHelper.personalInfoFields.contains(type))
        .toList();

    String? finalSelectedType;
    bool isWideScreen = MediaQuery.of(context).size.width > 600;

    finalSelectedType = await showDialog<String>(
      context: context,
      builder: (BuildContext dialogContext) {
        List<Widget> resolvedItemsForDialog = [];
        if (personalInfoTypes.isNotEmpty) {
          resolvedItemsForDialog.add(
            PopupMenuButton<String>(
              tooltip: FormStrings.personalInfo,
              offset: isWideScreen ? const Offset(160, 0) : const Offset(20, 0),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(8.0),
              ),
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
                          color: Theme.of(context).textTheme.bodyLarge?.color,
                        ),
                        const SizedBox(width: 12),
                        Text(FormHelper.fieldTypeToLocale(type)),
                      ],
                    ),
                  );
                }).toList();
              },
              child: ListTile(
                leading: Icon(
                  Icons.person_search_outlined,
                  size: 20,
                  color: Theme.of(context).textTheme.bodyLarge?.color,
                ),
                title: Text(FormStrings.personalInfo),
                trailing: Icon(
                  Icons.chevron_right,
                  color: Theme.of(context).textTheme.bodyLarge?.color,
                ),
                dense: true,
              ),
            ),
          );
          resolvedItemsForDialog.add(const Divider(height: 1, thickness: 0.5));
        }

        resolvedItemsForDialog.addAll(
          otherTypes.map((type) {
            return ListTile(
              leading: Icon(
                FormHelper.fieldTypeIcons[type] ?? Icons.circle_outlined,
                size: 20,
                color: Theme.of(context).textTheme.bodyLarge?.color,
              ),
              title: Text(FormHelper.fieldTypeToLocale(type)),
              dense: true,
              onTap: () {
                Navigator.of(dialogContext).pop(type);
              },
            );
          }).toList(),
        );

        if (resolvedItemsForDialog.isEmpty) {
          resolvedItemsForDialog.add(
            Center(
              child: Padding(
                padding: const EdgeInsets.all(16.0),
                child: Text(FormStrings.noFieldsAvailable),
              ),
            ),
          );
        }

        return AlertDialog(
          title: Text(FormStrings.addFieldTitle),
          contentPadding: const EdgeInsets.symmetric(vertical: 8.0),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(8.0),
          ),
          content: SizedBox(
            width: 280,
            child: ListView(shrinkWrap: true, children: resolvedItemsForDialog),
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
    final form = _bundle!.form;
    final newField = FormFieldModel(
      type: type,
      order: form.relatedFields.length,
      isRequired: FormHelper.isAlwaysRequired(type),
      isHidden: false,
      isTicketField: false,
    );

    setState(() {
      form.relatedFields = List.from(form.relatedFields)..add(newField);
    });

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollController.hasClients) {
        _scrollController.animateTo(
          _scrollController.position.maxScrollExtent,
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeInOut,
        );
      }
    });
  }

  Widget _buildHtmlParent(BuildContext context) {
    if (_bundle == null)
      return const Scaffold(body: Center(child: CircularProgressIndicator()));

    return Scaffold(
      floatingActionButtonAnimator: _NoScalingAnimation(),
      floatingActionButtonLocation: FloatingActionButtonLocation.endDocked,
      floatingActionButton: Column(
        mainAxisAlignment: MainAxisAlignment.end,
        children: [
          FloatingActionButton(
            heroTag: "viewFormFab",
            onPressed: () {
              if (_formLink != null) {
                RouterService.navigate(context, "${FormPage.ROUTE}/$_formLink");
              }
            },
            tooltip: FormStrings.publicView,
            child: const Icon(Icons.remove_red_eye_outlined),
          ),
          const SizedBox.square(dimension: 12),
          FloatingActionButton(
            heroTag: "previewFormFab",
            onPressed: () {
              if (_formLink != null) {
                RouterService.navigate(
                  context,
                  "${FormPage.ROUTE}/$_formLink?preview=true",
                );
              }
            },
            tooltip: FormStrings.editorPreview,
            child: const Icon(Icons.developer_mode),
          ),
          const SizedBox.square(dimension: 12),
          if (RightsService.isOrderEditor())
            FloatingActionButton(
              heroTag: "addFieldFab",
              onPressed: _addNewField,
              tooltip: FormStrings.addFieldTitle,
              child: const Icon(Icons.add),
            ),
          const SizedBox.square(dimension: 64),
        ],
      ),
      // UPDATED: Check for bundle
      body: _bundle == null
          ? const Center(child: CircularProgressIndicator())
          : Align(
              alignment: Alignment.topCenter,
              child: ConstrainedBox(
                constraints: BoxConstraints(
                  maxWidth: StylesConfig.formMaxWidth,
                ),
                child: SingleChildScrollView(
                  controller: _scrollController,
                  child: Padding(
                    padding: const EdgeInsets.all(6),
                    child: Column(
                      children: [
                        _buildFormOpenToggleAndOffTextEditor(),
                        const Divider(thickness: 1, color: Colors.grey),
                        EditableHtmlField(
                          key: const ValueKey('form-header'),
                          html: _bundle!.form.header,
                          enabled: RightsService.isOrderEditor(),
                          coordinator: _htmlSave,
                          owner: HtmlMediaOwner.occasion(
                            _bundle!.form.occasionId,
                          ),
                          onChanged: (html) =>
                              setState(() => _bundle!.form.header = html),
                        ),
                        const SizedBox(height: 24),
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const SizedBox(height: 8),
                            Text(
                              FormStrings.dragToReorder,
                              style: Theme.of(context).textTheme.bodySmall,
                            ),
                          ],
                        ),
                        const SizedBox(height: 16),
                        FormFieldsGenerator(bundle: _bundle!),
                        const SizedBox(height: 102),
                      ],
                    ),
                  ),
                ),
              ),
            ),
      bottomNavigationBar: Container(
        color: ThemeConfig.appBarColor(),
        padding: const EdgeInsets.all(10),
        child: SafeArea(
          child: Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              TextButton(
                onPressed: RightsService.isOrderEditor() ? cancelEdit : null,
                child: Text(CommonStrings.storno),
              ),
              const SizedBox(width: 16),
              ElevatedButton(
                onPressed: RightsService.isOrderEditor() ? saveChanges : null,
                child: Text(CommonStrings.save),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _NoScalingAnimation extends FloatingActionButtonAnimator {
  @override
  Offset getOffset({
    required Offset begin,
    required Offset end,
    required double progress,
  }) {
    return end;
  }

  @override
  Animation<double> getRotationAnimation({required Animation<double> parent}) {
    return Tween<double>(begin: 1.0, end: 1.0).animate(parent);
  }

  @override
  Animation<double> getScaleAnimation({required Animation<double> parent}) {
    return Tween<double>(begin: 1.0, end: 1.0).animate(parent);
  }
}
