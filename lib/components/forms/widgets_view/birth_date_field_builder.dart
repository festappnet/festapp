import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_form_builder/flutter_form_builder.dart';
import 'package:fstapp/components/forms/models/holder_models/birth_date_field_holder.dart';
import 'package:fstapp/theme_config.dart';
import 'package:form_builder_validators/form_builder_validators.dart';
import 'package:fstapp/components/html/html_view.dart';

import 'form_field_builders.dart';
import 'form_helper.dart';
import '../models/holder_models/form_holder.dart';
import 'package:fstapp/components/_shared/common_strings.dart';
import 'package:fstapp/components/_shared/person_fields_strings.dart';

class BirthDateFieldBuilder extends StatefulWidget {
  final BirthDateFieldHolder fieldHolder;
  final DateTime? eventDate;
  final GlobalKey<FormBuilderState> formKey;
  final bool isCardDesign;

  const BirthDateFieldBuilder({
    super.key,
    required this.fieldHolder,
    this.eventDate,
    required this.formKey,
    this.isCardDesign = false,
  });

  static Widget buildBirthDateField({
    required BuildContext context,
    required BirthDateFieldHolder fieldHolder,
    DateTime? eventDate,
    required GlobalKey<FormBuilderState> formKey,
    required FormHolder formHolder,
  }) {
    final bool isCardDesign = FormHelper.isCardDesign(formHolder, fieldHolder);
    return BirthDateFieldBuilder(
      fieldHolder: fieldHolder,
      eventDate: eventDate,
      formKey: formKey,
      isCardDesign: isCardDesign,
    );
  }

  @override
  _BirthDateFieldBuilderState createState() => _BirthDateFieldBuilderState();
}

class _BirthDateFieldBuilderState extends State<BirthDateFieldBuilder> {
  DateTime? selectedDate;
  String? warningMessage;
  final TextEditingController _dateController = TextEditingController();
  final FocusNode _focusNode = FocusNode();

  @override
  void dispose() {
    _dateController.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final effectiveEventDate = widget.eventDate ?? DateTime.now();
    final int effectiveMinAge = widget.fieldHolder.minYear ?? 0;
    final int effectiveMaxAge = widget.fieldHolder.maxYear ?? 0;
    final recommendedEarliestDate = DateTime(
      effectiveEventDate.year - effectiveMaxAge,
      effectiveEventDate.month,
      effectiveEventDate.day,
    );
    final recommendedLatestDate = DateTime(
      effectiveEventDate.year - effectiveMinAge,
      effectiveEventDate.month,
      effectiveEventDate.day,
    );
    final pickerFirstDate =
        widget.fieldHolder.isHard ? recommendedEarliestDate : DateTime(1900);
    final pickerLastDate =
        widget.fieldHolder.isHard ? recommendedLatestDate : DateTime.now();
    final dateFormat = DateFormat.yMd(context.locale.toString());

    Widget fieldWidget = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        FormBuilderDateTimePicker(
          controller: _dateController,
          focusNode: _focusNode,
          name: widget.fieldHolder.id.toString(),
          initialValue: DateTime.tryParse(
              widget.fieldHolder.defaultValue?.toString() ?? ''),
          inputType: InputType.date,
          initialDatePickerMode: DatePickerMode.year,
          format: dateFormat,
          fieldHintText: dateFormat.pattern,
          decoration: InputDecoration(
            filled: true,
            fillColor: Colors.transparent,
            label: widget.isCardDesign
                ? null
                : FormFieldBuilders.buildTitleWidget(
                    widget.fieldHolder.title!,
                    widget.fieldHolder.isRequired,
                    context,
                    focusNode: _focusNode,
                    controller: _dateController,
                  ),
            hintText: widget.isCardDesign ? widget.fieldHolder.title : null,
          ),
          helpText: FormHelper.birthDateLabel(),
          firstDate: pickerFirstDate,
          lastDate: pickerLastDate,
          initialEntryMode: DatePickerEntryMode.calendar,
          inputFormatters: [LocaleDateInputFormatter(dateFormat: dateFormat)],
          validator: (value) {
            if (widget.fieldHolder.isRequired && value == null) {
              return FormBuilderValidators.required(
                  errorText: CommonStrings.fieldCannotBeEmpty)(value);
            }
            String? nextWarning;
            if (value != null &&
                effectiveMinAge != 0 &&
                effectiveMaxAge != 0 &&
                (value.isBefore(recommendedEarliestDate) ||
                    value.isAfter(recommendedLatestDate))) {
              final namedArgs = {
                "minAge": effectiveMinAge.toString(),
                "maxAge": effectiveMaxAge.toString(),
              };
              if (widget.fieldHolder.isHard) {
                return widget.fieldHolder.message.isNotEmpty
                    ? widget.fieldHolder.message.tr(namedArgs: namedArgs)
                    : PersonFieldsStrings.ageRestriction(
                        minAge: effectiveMinAge.toString(),
                        maxAge: effectiveMaxAge.toString());
              }
              nextWarning = widget.fieldHolder.message.isNotEmpty
                  ? widget.fieldHolder.message.tr(namedArgs: namedArgs)
                  : PersonFieldsStrings.ageOutsideRecommendedRange(
                      minAge: effectiveMinAge.toString(),
                      maxAge: effectiveMaxAge.toString());
            }
            if (warningMessage != nextWarning) {
              WidgetsBinding.instance.addPostFrameCallback((_) {
                if (!mounted) return;
                setState(() {
                  warningMessage = nextWarning;
                });
              });
            }
            return null;
          },
          onChanged: (value) {
            setState(() {
              selectedDate = value;
            });
            widget
                .formKey.currentState!.fields[widget.fieldHolder.id.toString()]
                ?.validate();
            WidgetsBinding.instance.addPostFrameCallback((_) {
              _dateController.selection =
                  TextSelection.collapsed(offset: _dateController.text.length);
              FocusScope.of(context).unfocus();
            });
          },
        ),
        if (warningMessage != null && !widget.fieldHolder.isHard)
          Padding(
            padding: const EdgeInsets.only(top: 8.0),
            child: HtmlView(
              html: warningMessage!,
              color: ThemeConfig.warningColor(context),
              fontSize: 13.0 * FormHelper.fontSizeFactor,
              isSelectable: true,
            ),
          ),
      ],
    );

    if (widget.isCardDesign) {
      bool hasError = widget.formKey.currentState
              ?.fields[widget.fieldHolder.id.toString()]?.hasError ??
          false;
      fieldWidget = FormHelper.buildCardWrapperDesign(
        context: context,
        fieldHolder: widget.fieldHolder,
        content: fieldWidget,
        hasError: hasError,
      );
    }

    return fieldWidget;
  }
}

class LocaleDateInputFormatter extends TextInputFormatter {
  final String pattern;
  final Set<String> allowedSeparators;

  LocaleDateInputFormatter({required DateFormat dateFormat})
      : pattern = dateFormat.pattern!,
        allowedSeparators = dateFormat.pattern!
            .replaceAll(RegExp(r'[0-9a-zA-Z]'), '')
            .split('')
            .toSet();

  @override
  TextEditingValue formatEditUpdate(
      TextEditingValue oldValue, TextEditingValue newValue) {
    final filtered = newValue.text.split('').where((ch) {
      return RegExp(r'\d').hasMatch(ch) || allowedSeparators.contains(ch);
    }).join();
    return newValue.copyWith(text: filtered);
  }
}
