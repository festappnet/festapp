import 'email_suffix_confirmation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_form_builder/flutter_form_builder.dart';
import 'package:form_builder_validators/form_builder_validators.dart';
import 'package:fstapp/components/forms/logic/phone_country_codes.dart';
import 'package:fstapp/components/forms/models/holder_models/field_holder.dart';
import 'package:fstapp/components/forms/models/holder_models/form_holder.dart';
import 'package:fstapp/components/forms/widgets_view/form_field_builders.dart';
import 'package:fstapp/components/forms/widgets_view/form_helper.dart';
import 'package:fstapp/components/html/html_helper.dart';
import 'package:fstapp/theme_config.dart';
import 'package:fstapp/components/forms/widgets_view/phone_input_formatter.dart';

import '../form_strings.dart';
import 'package:fstapp/components/_shared/common_strings.dart';

class TextFieldBuilder extends StatelessWidget {
  final FieldHolder fieldHolder;
  final FormHolder formHolder;
  final Iterable<String> autofillHints;
  final bool isEmail;
  final bool isPhone;
  final bool isAddress;
  final bool isNationality;

  const TextFieldBuilder({
    super.key,
    required this.fieldHolder,
    required this.formHolder,
    this.autofillHints = const [],
    this.isEmail = false,
    this.isPhone = false,
    this.isAddress = false,
    this.isNationality = false,
  });

  @override
  Widget build(BuildContext context) {
    if (!FormHelper.isCardDesign(formHolder, fieldHolder) &&
        HtmlHelper.isHtmlEmptyOrNull(fieldHolder.description)) {
      return _buildStandardTextField(context);
    } else {
      return _buildCardDesignTextField(context);
    }
  }

  Widget _withEmailConfirmation(FormFieldState<String?> field, Widget input) {
    if (!isEmail) return input;
    return EmailSuffixField(
      session: formHolder.emailSuffixConfirmations,
      field: field,
      name: fieldHolder.id.toString(),
      eligible: !fieldHolder.isHidden,
      informal: formHolder.communicationTone == 'informal',
      child: input,
    );
  }

  Widget _buildStandardTextField(BuildContext context) {
    List<String? Function(String?)> validators = [];

    if (fieldHolder.isRequired) {
      validators.add(FormBuilderValidators.required(
          errorText: CommonStrings.fieldCannotBeEmpty));
    }

    if (isEmail) {
      validators.add(FormBuilderValidators.email(
        checkNullOrEmpty: false,
        errorText: FormHelper.emailInvalidMessage(),
      ));
    }

    if (isPhone) {
      validators.add(FormBuilderValidators.phoneNumber(
        regex: RegExp(r'^\+?[0-9]{' +
            PhoneInputFormatter.kMaxPhoneNumberLength.toString() +
            r'}$'),
        checkNullOrEmpty: false,
        errorText: FormStrings.phoneFormatValidation,
      ));
    }

    return FormBuilderField<String?>(
      name: fieldHolder.id.toString(),
      initialValue:
          fieldHolder.defaultValue?.toString() ?? (isPhone ? '+420' : null),
      validator: validators.isNotEmpty
          ? FormBuilderValidators.compose(validators)
          : null,
      autovalidateMode: isPhone
          ? AutovalidateMode.onUnfocus
          : AutovalidateMode.onUserInteraction,
      builder: (field) {
        final input = _StandardTextField(
          field: field,
          fieldHolder: fieldHolder,
          formHolder: formHolder,
          isPhone: isPhone,
          isEmail: isEmail,
          autofillHints: autofillHints,
        );
        return _withEmailConfirmation(field, input);
      },
    );
  }

  Widget _buildCardDesignTextField(BuildContext context) {
    List<String? Function(String?)> validators = [];

    if (fieldHolder.isRequired) {
      validators.add(FormBuilderValidators.required(
          errorText: CommonStrings.fieldCannotBeEmpty));
    }

    if (isEmail) {
      validators.add(FormBuilderValidators.email(
        checkNullOrEmpty: false,
        errorText: FormHelper.emailInvalidMessage(),
      ));
    }

    if (isPhone) {
      validators.add(FormBuilderValidators.phoneNumber(
        regex: RegExp(r'^\+?[0-9]{' +
            PhoneInputFormatter.kMaxPhoneNumberLength.toString() +
            r'}$'),
        checkNullOrEmpty: false,
        errorText: FormStrings.phoneFormatValidation,
      ));
    }

    return FormBuilderField<String?>(
      name: fieldHolder.id.toString(),
      initialValue:
          fieldHolder.defaultValue?.toString() ?? (isPhone ? '+420' : null),
      validator: FormBuilderValidators.compose(validators),
      autovalidateMode: isPhone
          ? AutovalidateMode.onUnfocus
          : AutovalidateMode.onUserInteraction,
      builder: (field) {
        final input = _CardTextField(
          field: field,
          fieldHolder: fieldHolder,
          formHolder: formHolder,
          autofillHints: autofillHints,
          isPhone: isPhone,
          isEmail: isEmail,
        );
        return _withEmailConfirmation(field, input);
      },
    );
  }
}

class _StandardTextField extends StatefulWidget {
  final FormFieldState<String?> field;
  final FieldHolder fieldHolder;
  final FormHolder formHolder;
  final bool isPhone;
  final bool isEmail;
  final Iterable<String> autofillHints;

  const _StandardTextField({
    required this.field,
    required this.fieldHolder,
    required this.formHolder,
    required this.isPhone,
    required this.isEmail,
    this.autofillHints = const [],
  });

  @override
  State<_StandardTextField> createState() => _StandardTextFieldState();
}

class _StandardTextFieldState extends State<_StandardTextField> {
  late final TextEditingController _controller;
  final FocusNode _focusNode = FocusNode();
  bool _showPrefixes = false;

  @override
  void initState() {
    super.initState();
    // Initialize controller with starting value from field
    String? initialValue = widget.field.value;
    if (widget.isPhone && (initialValue == null || initialValue.isEmpty)) {
      initialValue = '+420';
    }
    _controller = TextEditingController(text: initialValue);
    _focusNode.addListener(_handleFocusChange);
  }

  @override
  void didUpdateWidget(covariant _StandardTextField oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.field.value != null && widget.field.value != _controller.text) {
      _controller.text = widget.field.value!;
    }
  }

  @override
  void dispose() {
    _focusNode.removeListener(_handleFocusChange);
    _controller.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  void _handleFocusChange() {
    if (_focusNode.hasFocus) {
      setState(() {
        _showPrefixes = true;
      });
    } else {
      Future.delayed(const Duration(milliseconds: 200), () {
        if (mounted && !_focusNode.hasFocus) {
          setState(() {
            _showPrefixes = false;
          });
        }
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        TextField(
          enabled: widget.field.widget.enabled &&
              (FormBuilder.of(context)?.enabled ?? true),
          controller: _controller,
          focusNode: _focusNode,
          maxLines: null,
          autofillHints: widget.autofillHints,
          inputFormatters: widget.isPhone ? [PhoneInputFormatter()] : null,
          decoration: InputDecoration(
            filled: true,
            fillColor: Colors.transparent,
            hintText: widget.isPhone ? FormStrings.phoneFormatHint : null,
            label: FormFieldBuilders.buildTitleWidget(
              widget.fieldHolder.title!,
              widget.fieldHolder.isRequired,
              context,
              focusNode: _focusNode,
              controller: _controller,
            ),
            errorText: _focusNode.hasFocus ? null : widget.field.errorText,
          ),
          onChanged: (value) {
            widget.field.didChange(value);
          },
        ),
        if (widget.isPhone && _showPrefixes)
          _PhonePrefixHelpers(
            prefixes: widget.formHolder.phonePrefixes,
            onPrefixSelected: (prefix) {
              // Keep focus to prevent onUnfocus validation logic triggered by focus loss
              _focusNode.requestFocus();

              String current = _controller.text;
              String newText = _applyPrefix(current, prefix);
              _controller.value = TextEditingValue(
                text: newText,
                selection: TextSelection.collapsed(offset: newText.length),
              );
              widget.field.didChange(newText);
            },
          ),
      ],
    );
  }
}

class _CardTextField extends StatefulWidget {
  final FormFieldState<String?> field;
  final FieldHolder fieldHolder;
  final FormHolder formHolder;
  final Iterable<String> autofillHints;
  final bool isPhone;
  final bool isEmail;

  const _CardTextField({
    required this.field,
    required this.fieldHolder,
    required this.formHolder,
    required this.autofillHints,
    required this.isPhone,
    required this.isEmail,
  });

  @override
  _CardTextFieldState createState() => _CardTextFieldState();
}

class _CardTextFieldState extends State<_CardTextField> {
  late final TextEditingController _controller;
  final FocusNode _focusNode = FocusNode();
  bool _showPrefixes = false;

  @override
  void initState() {
    super.initState();
    String? initialValue = widget.field.value;
    if (widget.isPhone && (initialValue == null || initialValue.isEmpty)) {
      initialValue = '+420';
    }
    _controller = TextEditingController(text: initialValue);
    _focusNode.addListener(_handleFocusChange);
  }

  void _handleFocusChange() {
    if (widget.isPhone) {
      if (_focusNode.hasFocus) {
        setState(() {
          _showPrefixes = true;
        });
      } else {
        Future.delayed(const Duration(milliseconds: 200), () {
          if (mounted && !_focusNode.hasFocus) {
            setState(() {
              _showPrefixes = false;
            });
          }
        });
      }
    }
  }

  @override
  void dispose() {
    _focusNode.removeListener(_handleFocusChange);
    _controller.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  @override
  void didUpdateWidget(covariant _CardTextField oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.field.value != null && widget.field.value != _controller.text) {
      _controller.text = widget.field.value!;
    }
  }

  TextInputType _getKeyboardType() {
    if (widget.isPhone) {
      return TextInputType.phone;
    }
    if (widget.isEmail) {
      return TextInputType.emailAddress;
    }
    return TextInputType.text;
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
            enabled: widget.field.widget.enabled &&
                (FormBuilder.of(context)?.enabled ?? true),
            controller: _controller,
            focusNode: _focusNode,
            maxLines: null,
            autofillHints: widget.autofillHints,
            keyboardType: _getKeyboardType(),
            inputFormatters: widget.isPhone ? [PhoneInputFormatter()] : null,
            decoration: InputDecoration(
              hintText: widget.isPhone
                  ? FormStrings.phoneFormatHint
                  : widget.formHolder.communicationTone == 'informal'
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
          ClipRect(
            child: AnimatedSize(
              alignment: Alignment.topCenter,
              duration: const Duration(milliseconds: 300),
              curve: Curves.easeInOut,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (widget.isPhone && _showPrefixes)
                    _PhonePrefixHelpers(
                      prefixes: widget.formHolder.phonePrefixes,
                      onPrefixSelected: (prefix) {
                        // Keep focus to prevent onUnfocus validation
                        _focusNode.requestFocus();

                        String current = _controller.text;
                        String newText = _applyPrefix(current, prefix);
                        _controller.value = TextEditingValue(
                          text: newText,
                          selection:
                              TextSelection.collapsed(offset: newText.length),
                        );
                        widget.field.didChange(newText);
                      },
                    ),
                  if (widget.field.hasError && !_focusNode.hasFocus)
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
            ),
          ),
        ],
      ),
    );
  }
}

String _applyPrefix(String current, String prefix) {
  String result = current;
  if (current.startsWith(prefix)) {
    result = current;
  } else if (current.startsWith('+420')) {
    result = prefix + current.substring(4);
  } else if (current.startsWith('+421')) {
    result = prefix + current.substring(4);
  } else if (current.startsWith('+')) {
    result = prefix +
        current.substring(
            current.indexOf(' ') > 0 ? current.indexOf(' ') : current.length);
  } else {
    result = prefix + current;
  }

  // Clean and enforce max length using shared logic
  String cleaned = PhoneInputFormatter.cleanPhoneNumber(result);

  // Re-apply formatting to the result
  return PhoneInputFormatter.formatPhoneNumber(cleaned);
}

class _PhonePrefixHelpers extends StatefulWidget {
  final Function(String) onPrefixSelected;
  final List<String> prefixes;

  const _PhonePrefixHelpers(
      {required this.onPrefixSelected, this.prefixes = const []});

  @override
  State<_PhonePrefixHelpers> createState() => _PhonePrefixHelpersState();
}

class _PhonePrefixHelpersState extends State<_PhonePrefixHelpers> {
  @override
  Widget build(BuildContext context) {
    // Default to +420, +421 if empty
    final prefixes =
        widget.prefixes.isNotEmpty ? widget.prefixes : ['+420', '+421'];

    return Padding(
      padding: const EdgeInsets.only(top: 8.0),
      child: Wrap(
        spacing: 8.0,
        children: prefixes.map((p) {
          String label = p;
          final iso = PhoneCountryCodes.getIso(p);
          if (iso != null) {
            label = '$iso $p';
          }
          return _buildChip(context, label, p);
        }).toList(),
      ),
    );
  }

  Widget _buildChip(BuildContext context, String label, String value) {
    return InkWell(
      onTap: () => widget.onPrefixSelected(value),
      borderRadius: BorderRadius.circular(12),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        decoration: BoxDecoration(
          color: Theme.of(context).primaryColor.withOpacity(0.1),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
              color: Theme.of(context).primaryColor.withOpacity(0.3)),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 12,
            color: Theme.of(context).primaryColor,
            fontWeight: FontWeight.w500,
          ),
        ),
      ),
    );
  }
}
