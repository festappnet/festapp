import 'package:material_ui/material_ui.dart';
import 'package:flutter_form_builder/flutter_form_builder.dart';
import 'package:form_builder_validators/form_builder_validators.dart';
import 'package:fstapp/components/forms/models/holder_models/field_holder.dart';
import 'package:fstapp/components/forms/models/holder_models/form_holder.dart';
import 'package:fstapp/components/forms/widgets_view/form_field_builders.dart';
import 'package:fstapp/components/forms/widgets_view/form_helper.dart';
import 'package:fstapp/components/html/html_helper.dart';
import 'package:fstapp/theme_config.dart';

import '../form_strings.dart';
import 'package:fstapp/components/_shared/common_strings.dart';

class BirthYearFieldBuilder extends StatelessWidget {
  final FieldHolder fieldHolder;
  final FormHolder formHolder;

  const BirthYearFieldBuilder({
    super.key,
    required this.fieldHolder,
    required this.formHolder,
  });

  /// Returns the specific validators for the Birth Year field.
  List<String? Function(String?)> _getValidators(FieldHolder fieldHolder) {
    return [
      if (fieldHolder.isRequired)
        FormBuilderValidators.required(
            errorText: CommonStrings.fieldCannotBeEmpty),
      (value) {
        if (value == null || value.isEmpty) {
          // Let FormBuilderValidators.required() handle the empty case
          return null;
        }
        if (int.tryParse(value) == null) {
          return NumericValidator().translatedErrorText;
        }
        final numericValue = int.parse(value);
        final maxYear = DateTime.now().year;
        if (numericValue < 1900 || numericValue > maxYear) {
          return RangeValidator(maxYear, 1900).translatedErrorText;
        }
        return null;
      },
    ];
  }

  @override
  Widget build(BuildContext context) {
    if (!FormHelper.isCardDesign(formHolder, fieldHolder) &&
        HtmlHelper.isHtmlEmptyOrNull(fieldHolder.description)) {
      return _buildStandardBirthYearField(context);
    } else {
      return _buildCardDesignBirthYearField(context);
    }
  }

  Widget _buildStandardBirthYearField(BuildContext context) {
    FocusNode focusNode = FocusNode();
    return FormBuilderTextField(
      name: fieldHolder.id.toString(),
      autofillHints: [AutofillHints.birthdayYear],
      focusNode: focusNode,
      decoration: InputDecoration(
        label: FormFieldBuilders.buildTitleWidget(
          fieldHolder.title!,
          fieldHolder.isRequired,
          context,
          focusNode: focusNode,
        ),
        filled: true,
        fillColor: Colors.transparent,
      ),
      validator: FormBuilderValidators.compose(_getValidators(fieldHolder)),
      keyboardType: TextInputType.number,
    );
  }

  Widget _buildCardDesignBirthYearField(BuildContext context) {
    return ClipRect(
      child: AnimatedSize(
        alignment: Alignment.topCenter,
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeInOut,
        child: FormBuilderField<String?>(
          name: fieldHolder.id.toString(),
          validator: FormBuilderValidators.compose(_getValidators(fieldHolder)),
          autovalidateMode: AutovalidateMode.onUserInteraction,
          builder: (field) {
            return _CardBirthYearField(
              field: field,
              fieldHolder: fieldHolder,
              formHolder: formHolder,
            );
          },
        ),
      ),
    );
  }
}

class _CardBirthYearField extends StatefulWidget {
  final FormFieldState<String?> field;
  final FieldHolder fieldHolder;
  final FormHolder formHolder;

  const _CardBirthYearField({
    required this.field,
    required this.fieldHolder,
    required this.formHolder,
  });

  @override
  _CardBirthYearFieldState createState() => _CardBirthYearFieldState();
}

class _CardBirthYearFieldState extends State<_CardBirthYearField> {
  late final TextEditingController _controller;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: widget.field.value);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  void didUpdateWidget(covariant _CardBirthYearField oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.field.value != null && widget.field.value != _controller.text) {
      _controller.text = widget.field.value!;
    }
  }

  @override
  Widget build(BuildContext context) {
    return FormHelper.buildCardWrapperDesign(
      context: context,
      fieldHolder: widget.fieldHolder,
      hasError: widget.field.hasError,
      content: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          TextField(
            controller: _controller,
            autofillHints: const [AutofillHints.birthdayYear],
            maxLines: 1,
            keyboardType: TextInputType.number,
            decoration: InputDecoration(
              hintText: widget.formHolder.communicationTone == 'informal'
                  ? FormStrings.typeHere_informal
                  : FormStrings.typeHere,
              isDense: true,
              contentPadding: const EdgeInsets.fromLTRB(2, 12, 2, 12),
              border: const UnderlineInputBorder(),
              focusedBorder: UnderlineInputBorder(
                borderSide: BorderSide(
                    color: Theme.of(context).primaryColor, width: 2.0),
              ),
              errorBorder: UnderlineInputBorder(
                borderSide: BorderSide(
                    color: ThemeConfig.redColor(context), width: 1.0),
              ),
              focusedErrorBorder: UnderlineInputBorder(
                borderSide: BorderSide(
                    color: ThemeConfig.redColor(context), width: 2.0),
              ),
            ),
            onChanged: (value) {
              widget.field.didChange(value.isEmpty ? null : value);
            },
          ),
          if (widget.field.hasError)
            Padding(
              padding: const EdgeInsets.only(top: 8.0, left: 2.0),
              child: Text(
                widget.field.errorText!,
                style: TextStyle(
                  color: ThemeConfig.redColor(context),
                  fontSize: 12,
                ),
              ),
            ),
        ],
      ),
    );
  }
}
