import 'package:material_ui/material_ui.dart';
import 'package:flutter_form_builder/flutter_form_builder.dart';
import 'package:festapp_core/forms.dart';
import 'package:form_builder_validators/form_builder_validators.dart';
import 'package:fstapp/theme_config.dart';
import '../form_strings.dart';
import 'package:fstapp/components/_shared/common_strings.dart';
import '../models/holder_models/field_holder.dart';
import '../models/holder_models/form_holder.dart';
import 'form_helper.dart';
import 'option_field_helper.dart';
import 'package:fstapp/components/features/feature_service.dart';

/// Builds a single-select field (radio). Decides whether to show
/// a basic radio group or a card-based option list based on whether
/// any option has a description.
/// Also handles filtering by currency if options have different currencies.
class RadioFieldBuilder {
  /// Builds a currency-aware radio field.
  static Widget buildRadioField(
    BuildContext context,
    FieldHolder fieldHolder,
    List<FormOptionDefinition> optionsIn,
    FormHolder formHolder,
  ) {
    return _CurrencyFilteredRadioField(
      fieldHolder: fieldHolder,
      optionsIn: optionsIn,
      formHolder: formHolder,
    );
  }

  /// Resolves the configured default to a matching FormOptionDefinition.
  /// Matches by option.title (select_one stores titles) OR option.id
  /// (product_type stores product IDs). Returns null if no match.
  static FormOptionDefinition? resolveDefault(
      FieldHolder fieldHolder, List<FormOptionDefinition> options) {
    final raw = fieldHolder.defaultValue;
    if (raw is FormOptionDefinition) {
      for (final option in options) {
        if (option.id == raw.id) return option;
      }
      return null;
    }
    if (raw is! String || raw.isEmpty) return null;
    for (final o in options) {
      if (o.title == raw || o.id == raw) return o;
    }
    return null;
  }

  /// A simple radio group when none of the options have a description.
  static Widget _buildBasicRadioField(
    BuildContext context,
    FieldHolder fieldHolder,
    List<FormOptionDefinition> optionsIn,
    FormHolder formHolder,
  ) {
    return _BasicRadioFieldWidget(
      fieldHolder: fieldHolder,
      optionsIn: optionsIn,
      formHolder: formHolder,
    );
  }

  /// A card-based radio list when at least one option has a description.
  /// This version uses the FormBuilderField's builder to obtain the live error state.
  static Widget _buildCardDesignRadioField(
    BuildContext context,
    FieldHolder fieldHolder,
    List<FormOptionDefinition> optionsIn,
    FormHolder formHolder,
  ) {
    // If there are no options to display for the current filter, show a message.
    if (optionsIn.isEmpty) {
      return FormHelper.buildCardWrapperDesign(
          context: context,
          fieldHolder: fieldHolder,
          hasError: false,
          content: Center(child: Text(FormStrings.noOptionsForCurrency)));
    }
    return ClipRect(
      child: AnimatedSize(
        alignment: Alignment.topCenter,
        duration: Duration(milliseconds: 300),
        curve: Curves.easeInOut,
        child: FormBuilderField<FormOptionDefinition?>(
          key: ValueKey(fieldHolder.id.toString() +
              optionsIn.toString()), // Add key to force rebuild
          name: fieldHolder.id.toString(),
          validator: fieldHolder.isRequired
              ? FormBuilderValidators.required(
                  errorText: CommonStrings.fieldCannotBeEmpty)
              : null,
          initialValue: resolveDefault(fieldHolder, optionsIn),
          builder: (field) {
            // Use the field's error state to update the card wrapper.
            return FormHelper.buildCardWrapperDesign(
              context: context,
              fieldHolder: fieldHolder,
              content: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Build the list of option cards.
                  Column(
                    children: optionsIn
                        .map((o) => _buildRadioOptionCard(
                            context, field, o, formHolder))
                        .toList(),
                  ),
                  // Animate the appearance/disappearance of the "Clear selection" button.
                  AnimatedSwitcher(
                    duration: Duration(milliseconds: 300),
                    child: field.value != null
                        ? Padding(
                            key: ValueKey('removeButton'),
                            padding: const EdgeInsets.only(top: 8.0),
                            child: TextButton(
                              onPressed: () {
                                field.didChange(null);
                                formHolder.controller?.updateTotalPrice?.call();
                                field.validate();
                              },
                              child: Text(FormStrings.clearSelection),
                            ),
                          )
                        : SizedBox(key: ValueKey('empty')),
                  ),
                  // Display error text below the field if there is one.
                  if (field.errorText != null)
                    Padding(
                      padding: const EdgeInsets.only(top: 8.0),
                      child: Text(
                        field.errorText!,
                        style: TextStyle(
                          color: ThemeConfig.redColor(context),
                          fontSize: 12,
                        ),
                      ),
                    ),
                ],
              ),
              hasError: field.hasError,
            );
          },
        ),
      ),
    );
  }

  /// Builds a single card with a radio button for the given option.
  static Widget _buildRadioOptionCard(
    BuildContext context,
    FormFieldState<FormOptionDefinition?> field,
    FormOptionDefinition o,
    FormHolder formHolder,
  ) {
    // If the option is a product option and is disabled, mark it accordingly.
    final bool isDisabled = o is FormOptionProductModel && !o.isAvailable;
    final title = OptionFieldHelper.buildOptionTitle(context, o);
    // If disabled, update text style to use the disabled color and append "Unavailable".
    final effectiveTitle =
        isDisabled ? "$title (${FormStrings.unavailable})" : title;
    final isSelected = (field.value == o);

    String? effectiveDescription = o.description;
    // Meta surcharge sits ABOVE original description.
    final metaText = OptionFieldHelper.buildMetaSurchargeText(context, o);
    if (metaText != null) {
      effectiveDescription = effectiveDescription != null
          ? "$metaText<br>$effectiveDescription"
          : metaText;
    }
    final showDepositInfo =
        formHolder.getTicket()?.showDepositDescription ?? true;
    if (showDepositInfo &&
        FeatureService.isDepositChoiceAvailable() &&
        o is FormOptionProductModel &&
        o.depositAmount != null) {
      final depositText = OptionFieldHelper.buildDepositText(context, o);
      effectiveDescription =
          "<span style='font-weight: bold;'>$depositText</span>"
          "${effectiveDescription != null ? "<br>$effectiveDescription" : ""}";
    }

    final optionCard = OptionFieldHelper.buildOptionCard(
      context: context,
      isSelected: isSelected,
      title: effectiveTitle,
      priceText: OptionFieldHelper.buildPriceText(context, o),
      description: effectiveDescription,
      leading: Radio<FormOptionDefinition>(
        value: o,
        groupValue: field.value,
        onChanged: isDisabled
            ? null
            : (val) {
                field.didChange(val);
                formHolder.controller?.updateTotalPrice?.call();
                field.validate();
              },
      ),
      onTap: isDisabled
          ? null
          : () {
              field.didChange(o);
              formHolder.controller?.updateTotalPrice?.call();
              field.validate();
            },
    );
    // Wrap the card in an Opacity widget to grey it out if disabled.
    return isDisabled ? Opacity(opacity: 0.5, child: optionCard) : optionCard;
  }
}

/// A wrapper widget that handles currency filtering for radio fields.
class _CurrencyFilteredRadioField extends StatefulWidget {
  final FieldHolder fieldHolder;
  final List<FormOptionDefinition> optionsIn;
  final FormHolder formHolder;

  const _CurrencyFilteredRadioField({
    required this.fieldHolder,
    required this.optionsIn,
    required this.formHolder,
  });

  @override
  State<_CurrencyFilteredRadioField> createState() =>
      _CurrencyFilteredRadioFieldState();
}

class _CurrencyFilteredRadioFieldState
    extends State<_CurrencyFilteredRadioField> {
  final List<String> _availableCurrencies = [];
  String? _selectedCurrency;

  @override
  void initState() {
    super.initState();
    _initializeCurrencies();
  }

  void _initializeCurrencies() {
    final currencies = <String>{};
    for (final option in widget.optionsIn) {
      if (option is FormOptionProductModel &&
          option.price > 0 &&
          option.currencyCode != null) {
        currencies.add(option.currencyCode!);
      }
    }
    _availableCurrencies.addAll(currencies.toList()..sort());
    if (_availableCurrencies.isNotEmpty) {
      _selectedCurrency = _availableCurrencies.first;
    }
  }

  void _onCurrencyChanged(String newCurrency) {
    setState(() {
      _selectedCurrency = newCurrency;
    });
  }

  Widget _buildCurrencyToggle() {
    if (_availableCurrencies.length <= 1) {
      return const SizedBox.shrink();
    }

    return Padding(
      padding: const EdgeInsets.only(bottom: 12.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            FormStrings.inWhatCurrency,
            style: TextStyle(
              fontWeight: FontWeight.bold,
              color: Theme.of(context).colorScheme.onSurface.withOpacity(0.8),
            ),
          ),
          const SizedBox(height: 8),
          ToggleButtons(
            isSelected: _availableCurrencies
                .map((c) => c == _selectedCurrency)
                .toList(),
            onPressed: (index) {
              _onCurrencyChanged(_availableCurrencies[index]);
            },
            borderRadius: BorderRadius.circular(8.0),
            constraints: BoxConstraints(minHeight: 40.0, minWidth: 80.0),
            children:
                _availableCurrencies.map((c) => Text(c.toUpperCase())).toList(),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    List<FormOptionDefinition> filteredOptions;

    // Filter options based on the selected currency
    if (_selectedCurrency == null) {
      filteredOptions = widget.optionsIn;
    } else {
      filteredOptions = widget.optionsIn.where((option) {
        if (option is FormOptionProductModel &&
            option.price > 0 &&
            option.currencyCode != null) {
          return option.currencyCode == _selectedCurrency;
        }
        // Always include non-product options or free products
        return true;
      }).toList();
    }

    // If the currently selected value is not in the filtered list, clear it.
    final formState = FormBuilder.of(context);
    final fieldState = formState?.fields[widget.fieldHolder.id.toString()];
    if (fieldState?.value != null &&
        !filteredOptions.contains(fieldState?.value)) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          fieldState?.didChange(null);
          widget.formHolder.controller?.updateTotalPrice?.call();
        }
      });
    }

    final fieldWidget = FormHelper.isCardDesign(
            widget.formHolder, widget.fieldHolder)
        ? RadioFieldBuilder._buildCardDesignRadioField(
            context, widget.fieldHolder, filteredOptions, widget.formHolder)
        : RadioFieldBuilder._buildBasicRadioField(
            context, widget.fieldHolder, filteredOptions, widget.formHolder);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildCurrencyToggle(),
        fieldWidget,
      ],
    );
  }
}

// Private StatefulWidget that implements the basic radio field with the remove button.
class _BasicRadioFieldWidget extends StatefulWidget {
  final FieldHolder fieldHolder;
  final List<FormOptionDefinition> optionsIn;
  final FormHolder formHolder;

  const _BasicRadioFieldWidget({
    required this.fieldHolder,
    required this.optionsIn,
    required this.formHolder,
  });

  @override
  _BasicRadioFieldWidgetState createState() => _BasicRadioFieldWidgetState();
}

class _BasicRadioFieldWidgetState extends State<_BasicRadioFieldWidget> {
  final GlobalKey<FormBuilderFieldState> _radioGroupKey =
      GlobalKey<FormBuilderFieldState>();

  @override
  Widget build(BuildContext context) {
    // If there are no options to display for the current filter, show nothing or a message.
    if (widget.optionsIn.isEmpty) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 16.0),
        child: Text(FormStrings.noOptionsForCurrency),
      );
    }

    final options = widget.optionsIn.map((o) {
      // If the option is a product option, check if it's disabled.
      final bool isDisabled = o is FormOptionProductModel && !o.isAvailable;
      final style = OptionFieldHelper.optionTitleTextStyle().copyWith(
        color: isDisabled ? Theme.of(context).disabledColor : null,
      );
      final title = OptionFieldHelper.buildOptionTitle(context, o);
      final effectiveTitle =
          isDisabled ? "$title (${FormStrings.unavailable})" : title;

      final priceText = OptionFieldHelper.buildPriceText(context, o);
      Widget labelWidget = priceText != null
          ? Row(
              children: [
                Expanded(child: Text(effectiveTitle, style: style)),
                const SizedBox(width: 8),
                Text(priceText,
                    style: style.copyWith(
                      fontWeight: FontWeight.bold,
                      color: isDisabled ? null : Theme.of(context).primaryColor,
                    )),
              ],
            )
          : Text(effectiveTitle, style: style);

      final showDepositInfo =
          widget.formHolder.getTicket()?.showDepositDescription ?? true;
      if (showDepositInfo &&
          FeatureService.isDepositChoiceAvailable() &&
          o is FormOptionProductModel &&
          o.depositAmount != null) {
        final depositText = OptionFieldHelper.buildDepositText(context, o);
        labelWidget = Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            labelWidget,
            const SizedBox(height: 2),
            Text(depositText,
                style: style.copyWith(
                    color: Theme.of(context)
                        .colorScheme
                        .onSurface
                        .withValues(alpha: 0.7),
                    fontSize: 13,
                    fontWeight: FontWeight.w500)),
          ],
        );
      }
      final metaText = OptionFieldHelper.buildMetaSurchargeText(context, o);
      if (metaText != null) {
        labelWidget = Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            labelWidget,
            const SizedBox(height: 2),
            Text(metaText,
                style: style.copyWith(
                    color: Theme.of(context)
                        .colorScheme
                        .onSurface
                        .withValues(alpha: 0.7),
                    fontSize: 13,
                    fontWeight: FontWeight.w500)),
          ],
        );
      }

      return FormBuilderFieldOption<FormOptionDefinition>(
        value: o,
        child: labelWidget,
      );
    }).toList();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        FormBuilderRadioGroup<FormOptionDefinition>(
          key: _radioGroupKey,
          // Re-create the widget when options change to reset state correctly
          name: widget.fieldHolder.id.toString(),
          decoration: FormHelper.buildInputDecoration(
            context: context,
            label: widget.fieldHolder.title ?? '',
            isRequired: widget.fieldHolder.isRequired,
          ),
          validator: widget.fieldHolder.isRequired
              ? FormBuilderValidators.required(
                  errorText: CommonStrings.fieldCannotBeEmpty)
              : null,
          initialValue: RadioFieldBuilder.resolveDefault(
              widget.fieldHolder, widget.optionsIn),
          options: options,
          orientation: OptionsOrientation.vertical,
          wrapDirection: Axis.vertical,
          onChanged: (val) {
            // Prevent selection change if the option is disabled.
            if (val is FormOptionProductModel && !val.isAvailable) {
              return;
            }
            // Trigger rebuild to show/hide the clear button
            setState(() {});
            _radioGroupKey.currentState?.validate();
            widget.formHolder.controller?.updateTotalPrice?.call();
          },
        ),
        if (_radioGroupKey.currentState?.value != null)
          Align(
            alignment: Alignment.centerLeft,
            child: OutlinedButton(
              onPressed: () {
                _radioGroupKey.currentState?.didChange(null);
                // Trigger rebuild to hide the clear button
                setState(() {});
                _radioGroupKey.currentState?.validate();
                widget.formHolder.controller?.updateTotalPrice?.call();
              },
              child: Text(FormStrings.clearSelection),
            ),
          ),
        Divider(
          thickness: 1,
          color: ThemeConfig.grey500(context),
        ),
      ],
    );
  }
}
