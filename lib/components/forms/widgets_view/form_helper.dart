import 'package:fstapp/components/eshop/order_item_strings.dart';
import 'package:festapp_core/forms.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:fstapp/components/blueprint/blueprint_seat.dart';
import 'package:fstapp/components/users/user_info_model.dart';
import 'package:material_ui/material_ui.dart';
import 'package:flutter_form_builder/flutter_form_builder.dart';
import 'package:fstapp/components/blueprint/blueprint_object_model.dart';
import 'package:fstapp/components/forms/models/holder_models/id_document_field_holder.dart';
import 'package:fstapp/components/forms/widgets_view/check_box_field_builder.dart';
import 'package:fstapp/components/forms/widgets_view/radio_field_builder.dart';
import 'package:fstapp/components/html/html_helper.dart';
import 'package:fstapp/services/utilities_all.dart';
import 'package:fstapp/theme_config.dart';
import 'package:fstapp/components/html/html_view.dart';
import '../../_shared/common_strings.dart';
import '../form_strings.dart';
import 'package:fstapp/components/_shared/person_fields_strings.dart';
import '../models/holder_models/birth_date_field_holder.dart';
import '../models/holder_models/field_holder.dart';
import '../models/holder_models/form_holder.dart';
import '../models/holder_models/ticket_holder.dart';
import 'birth_date_field_builder.dart';
import 'form_field_builders.dart';
import 'id_document_field_builder.dart';

class FormHelper {
  // Labels and messages
  static String noteLabel() => CommonStrings.note;
  static String nameLabel() => CommonStrings.name;
  static String surnameLabel() => PersonFieldsStrings.surname;
  static String cityLabel() => PersonFieldsStrings.city;
  static String spotLabel() => CommonStrings.spot;
  static String emailLabel() => PersonFieldsStrings.email;
  static String phoneLabel() => PersonFieldsStrings.phone;
  static String addressLabel() => PersonFieldsStrings.address;
  static String nationalityLabel() => PersonFieldsStrings.nationality;
  static String sexLabel() => PersonFieldsStrings.sexLabel;
  static String birthYearLabel() => PersonFieldsStrings.birthYear;
  static String birthDateLabel() => PersonFieldsStrings.birthDate;
  static String idDocumentLabel() => FormStrings.idCardPassportNumber;
  static String emailInvalidMessage() => PersonFieldsStrings.emailInvalid;
  static String maleLabel() => PersonFieldsStrings.male;
  static String femaleLabel() => PersonFieldsStrings.female;
  static String notSpecifiedLabel() => PersonFieldsStrings.notSpecified;

  static String ticketLabel() => OrderItemStrings.itemSingular;
  static String textLabel() => FormStrings.textFieldType;
  static String selectOneLabel() => FormStrings.singleChoice;
  static String selectManyLabel() => FormStrings.multipleChoice;
  static String productTypeLabel() => FormStrings.productType;

  static const Map<String, IconData> fieldTypeIcons = {
    FormMetadata.fieldTypeText: Icons.text_fields,
    FormMetadata.fieldTypeSelectOne: Icons.radio_button_checked,
    FormMetadata.fieldTypeSelectMany: Icons.check_box_outlined,
    FormMetadata.fieldTypeEmail: Icons.email,
    FormMetadata.fieldTypeName: Icons.person,
    FormMetadata.fieldTypeSurname: Icons.person_outline,
    FormMetadata.fieldTypeSex: Icons.wc,
    FormMetadata.fieldTypeCity: Icons.location_city,
    FormMetadata.fieldTypeAddress: Icons.home,
    FormMetadata.fieldTypeNationality: Icons.flag,
    FormMetadata.fieldTypeBirthYear: Icons.cake,
    FormMetadata.fieldTypeBirthDate: Icons.cake,
    FormMetadata.fieldTypeIdDocument: Icons.article,
    FormMetadata.fieldTypeNote: Icons.note,
    FormMetadata.fieldTypeSpot: Icons.event_seat,
    FormMetadata.fieldTypeProductType: Icons.category,
    FormMetadata.fieldTypeTicket: Icons.confirmation_number,
    FormMetadata.fieldTypePhone: Icons.phone,
  };

  static String fieldTypeToLocale(String fieldType) {
    switch (fieldType) {
      case FormMetadata.fieldTypeName:
        return nameLabel();
      case FormMetadata.fieldTypeSurname:
        return surnameLabel();
      case FormMetadata.fieldTypeCity:
        return cityLabel();
      case FormMetadata.fieldTypeAddress:
        return addressLabel();
      case FormMetadata.fieldTypeNationality:
        return nationalityLabel();
      case FormMetadata.fieldTypeEmail:
        return emailLabel();
      case FormMetadata.fieldTypeSex:
        return sexLabel();
      case FormMetadata.fieldTypeBirthYear:
        return birthYearLabel();
      case FormMetadata.fieldTypeNote:
        return noteLabel();
      case FormMetadata.fieldTypeSpot:
        return spotLabel();
      case FormMetadata.fieldTypeTicket:
        return ticketLabel();
      case FormMetadata.fieldTypeText:
        return textLabel();
      case FormMetadata.fieldTypeSelectOne:
        return selectOneLabel();
      case FormMetadata.fieldTypeSelectMany:
        return selectManyLabel();
      case FormMetadata.fieldTypeProductType:
        return productTypeLabel();
      case FormMetadata.fieldTypeBirthDate:
        return birthDateLabel();
      case FormMetadata.fieldTypeIdDocument:
        return idDocumentLabel();
      case FormMetadata.fieldTypePhone:
        return phoneLabel();
      default:
        return fieldType;
    }
  }

  static String fieldTypeValue(
      BuildContext context, String value, String? fieldType) {
    switch (fieldType) {
      case FormMetadata.fieldTypeSex:
        return UserInfoModel.sexToLocale(value);
      case FormMetadata.fieldTypeBirthDate:
        try {
          final DateTime parsedDate = DateTime.parse(value);
          final locale = Localizations.localeOf(context).toString();
          return DateFormat.yMMMMd(locale).format(parsedDate);
        } catch (e) {
          return value;
        }
      default:
        return value;
    }
  }

  static double fontSizeFactor = 1.2;

  static List<Widget> getAllFormFields(BuildContext context,
      GlobalKey<FormBuilderState> formKey, FormHolder formHolder) {
    return formHolder.fields
        .map<Widget>(
            (field) => createFormField(context, formKey, formHolder, field))
        .toList();
  }

  static List<Widget> getFormFields(
      BuildContext context,
      GlobalKey<FormBuilderState> formKey,
      FormHolder formHolder,
      List<FieldHolder> fields) {
    return fields
        .map<Widget>(
            (field) => createFormField(context, formKey, formHolder, field))
        .toList();
  }

// Helper method to scroll to the first invalid field in a given FormBuilder.
  static Future<void> scrollToInvalidField(
      GlobalKey<FormBuilderState> key) async {
    final fields = key.currentState?.fields;
    if (fields == null) return;
    for (final entry in fields.entries) {
      if (entry.value.hasError) {
        final fieldContext = entry.value.context;
        // Animate the scroll until the invalid widget is visible.
        await Scrollable.ensureVisible(
          fieldContext,
          duration: Duration(milliseconds: 500),
          alignment: 0, // Adjust alignment to bring widget into view.
        );
        break;
      }
    }
  }

  static Future<bool> saveValidateAndScroll(FormHolder formHolder) async {
    // Phase 1: Validate all forms without scrolling immediately.
    bool mainFormValid =
        formHolder.controller!.globalKey.currentState?.saveAndValidate() ??
            false;
    bool ticketsValid = true;

    // Store keys of forms that are invalid.
    final List<GlobalKey<FormBuilderState>> invalidFormKeys = [];

    if (!mainFormValid) {
      invalidFormKeys.add(formHolder.controller!.globalKey);
    }

    var ticketHolder = formHolder.getTicket();
    if (ticketHolder != null) {
      for (var ticket in ticketHolder.tickets) {
        bool ticketValid =
            ticket.ticketKey.currentState?.saveAndValidate() ?? false;
        if (!ticketValid) {
          ticketsValid = false;
          invalidFormKeys.add(ticket.ticketKey);
        }
      }
    }

    // If everything is valid, return true.
    if (mainFormValid && ticketsValid) {
      return formHolder.emailSuffixConfirmations.validate([
        formHolder.controller!.globalKey.currentState,
        if (ticketHolder != null)
          for (final ticket in ticketHolder.tickets)
            ticket.ticketKey.currentState,
      ]);
    }

    // Phase 2: Scroll to the first invalid field in the first invalid form.
    // Assumes that the main form is positioned above ticket forms.
    if (invalidFormKeys.isNotEmpty) {
      await scrollToInvalidField(invalidFormKeys.first);
    }

    return false;
  }

  static Map<String, dynamic> getDataFromForm(FormHolder formHolder,
      [bool? returnWithType]) {
    Map<String, dynamic> toReturn = {};
    for (var k in formHolder.fields) {
      var value = getFieldData(formHolder.controller!.globalKey, k);
      if (k.fieldType == FormMetadata.fieldTypeTicket) {
        toReturn[FormMetadata.fieldTypeTicket] = value;
      } else {
        if (returnWithType == true) {
          if (toReturn[FormMetadata.metaFields] == null) {
            toReturn[FormMetadata.metaFields] = {};
          }
          toReturn[FormMetadata.metaFields][k.fieldType] = value;
        } else {
          if (toReturn[FormMetadata.metaFields] == null) {
            toReturn[FormMetadata.metaFields] = [];
          }
          toReturn[FormMetadata.metaFields].add({k.id.toString(): value});
        }
      }
    }
    return toReturn;
  }

  static dynamic getFieldData(
      GlobalKey<FormBuilderState> formKey, FieldHolder fieldHolder) {
    var fieldValue =
        formKey.currentState?.fields[fieldHolder.id.toString()]?.value;

    switch (fieldHolder.fieldType) {
      case FormMetadata.fieldTypeSex:
        if (fieldValue == null) {
          return null;
        }
        return (fieldValue as FormOptionDefinition).id;
      case FormMetadata.fieldTypeBirthYear:
        return (fieldValue != null && fieldValue.isNotEmpty)
            ? int.tryParse(fieldValue.toString())
            : null;
      case FormMetadata.fieldTypeBirthDate:
        return (fieldValue is DateTime) ? fieldValue.toIso8601String() : null;
      case FormMetadata.fieldTypeIdDocument:
        if (fieldHolder is IdDocumentFieldHolder) {
          return fieldHolder.getIdDocumentData(formKey);
        }
        return null;
      case FormMetadata.fieldTypeSpot:
        if (fieldValue is BlueprintSeat) {
          return fieldValue.seat;
        }
        return null;
      case FormMetadata.fieldTypeTicket:
        List<Map<String, dynamic>> tickets = [];
        var ticket = fieldHolder as TicketHolder;
        for (int i = 0; i < ticket.tickets.length; i++) {
          final ticketKey = ticket.tickets[i].ticketKey;
          if (ticketKey.currentState == null &&
              ticket.tickets[i].blueprintAreaNodeId == null) continue;
          Map<String, dynamic> ticketData = {
            if (ticket.tickets[i].ticketId != null)
              'ticketId': ticket.tickets[i].ticketId,
          };
          for (var subFieldHolder in ticket.tickets[i].ticketValues) {
            if (ticketData[FormMetadata.metaFields] == null) {
              ticketData[FormMetadata.metaFields] = [];
            }
            var value = getFieldData(ticketKey, subFieldHolder) ??
                ticket.tickets[i].productDefaults[subFieldHolder.id];
            if (subFieldHolder.fieldType == FormMetadata.fieldTypeProductType &&
                (value == null || value == '')) {
              continue;
            }

            if (subFieldHolder.fieldType == FormMetadata.fieldTypeProductType &&
                subFieldHolder is OptionsFieldProductHolder &&
                subFieldHolder.selectionType ==
                    OptionsFieldProductSelectionType.selectMany) {
              if (value is List) {
                // Ensure value is a list before iterating
                for (var v in value) {
                  ticketData[FormMetadata.metaFields]
                      .add({subFieldHolder.fieldType: v});
                }
              }
            } else {
              ticketData[FormMetadata.metaFields].add({
                subFieldHolder.fieldType: value,
                if (subFieldHolder.fieldType !=
                    FormMetadata.fieldTypeProductType)
                  subFieldHolder.id.toString(): value,
              });
            }
          }
          if (ticket.tickets[i].seat != null) {
            ticketData[FormMetadata.fieldTypeSpot] =
                ticket.tickets[i].seat!.seat;
          }
          tickets.add(ticketData);
        }
        return tickets;
      case FormMetadata.fieldTypeSelectMany:
        if (fieldValue is List) {
          return fieldValue.map((e) {
            if (e is FormOptionDefinition) return e.title;
            return e.toString();
          }).join(FormMetadata.optionDelimiter);
        }
        return fieldValue;
      default:
        if (fieldValue is String) {
          return fieldValue.trim();
        }
        return fieldValue;
    }
  }

  static Widget createFormField(
      BuildContext context,
      GlobalKey<FormBuilderState> formKey,
      FormHolder formHolder,
      FieldHolder field) {
    final bool isRequiredField = field.isRequired;
    switch (field.fieldType) {
      case FormMetadata.fieldTypeText:
        return FormFieldBuilders.buildTextField(context, formHolder, field, []);
      case FormMetadata.fieldTypeNote:
        field.title = Utilities.replaceIfNullOrEmpty(field.title, noteLabel());
        return FormFieldBuilders.buildTextField(context, formHolder, field, []);
      case FormMetadata.fieldTypeName:
        field.title = Utilities.replaceIfNullOrEmpty(field.title, nameLabel());
        return FormFieldBuilders.buildTextField(
            context, formHolder, field, [AutofillHints.givenName]);
      case FormMetadata.fieldTypeSurname:
        field.title =
            Utilities.replaceIfNullOrEmpty(field.title, surnameLabel());
        return FormFieldBuilders.buildTextField(
            context, formHolder, field, [AutofillHints.familyName]);
      case FormMetadata.fieldTypeCity:
        field.title = Utilities.replaceIfNullOrEmpty(field.title, cityLabel());
        return FormFieldBuilders.buildTextField(
            context, formHolder, field, [AutofillHints.addressCity]);
      case FormMetadata.fieldTypeAddress:
        field.title =
            Utilities.replaceIfNullOrEmpty(field.title, addressLabel());
        return FormFieldBuilders.buildAddressField(context, formHolder, field);
      case FormMetadata.fieldTypeNationality:
        field.title =
            Utilities.replaceIfNullOrEmpty(field.title, nationalityLabel());
        return FormFieldBuilders.buildNationalityField(
            context, formHolder, field);
      case FormMetadata.fieldTypeSpot:
        field.title = Utilities.replaceIfNullOrEmpty(field.title, spotLabel());
        return FormFieldBuilders.buildSpotField(
            context, formKey, formHolder, field);
      case FormMetadata.fieldTypeEmail:
        field.title = Utilities.replaceIfNullOrEmpty(field.title, emailLabel());
        return FormFieldBuilders.buildEmailField(context, formHolder, field);
      case FormMetadata.fieldTypePhone:
        field.title = Utilities.replaceIfNullOrEmpty(field.title, phoneLabel());
        return FormFieldBuilders.buildPhoneNumber(context, formHolder, field);
      case FormMetadata.fieldTypeSex:
        field.title = Utilities.replaceIfNullOrEmpty(field.title, sexLabel());
        var sexOptions = [
          FormOptionDefinition(UserInfoModel.sexes[0], maleLabel()),
          FormOptionDefinition(UserInfoModel.sexes[1], femaleLabel()),
        ];
        if (!isRequiredField) {
          sexOptions.insert(
              0,
              FormOptionDefinition(
                  UserInfoModel.sexes[2], notSpecifiedLabel()));
        }
        return RadioFieldBuilder.buildRadioField(
            context, field, sexOptions, formHolder);
      case FormMetadata.fieldTypeSelectOne:
        var optionsField = field as OptionsFieldHolder;
        return RadioFieldBuilder.buildRadioField(
            context, optionsField, optionsField.options, formHolder);
      case FormMetadata.fieldTypeSelectMany:
        var optionsField = field as OptionsFieldHolder;
        return CheckboxFieldBuilder.buildSelectManyField(
            context, optionsField, optionsField.options, formHolder);
      case FormMetadata.fieldTypeProductType:
        var optionsField = field as OptionsFieldProductHolder;
        if (optionsField.selectionType ==
            OptionsFieldProductSelectionType.selectMany) {
          return CheckboxFieldBuilder.buildSelectManyField(
              context, optionsField, optionsField.options, formHolder);
        }
        return RadioFieldBuilder.buildRadioField(
            context, optionsField, optionsField.options, formHolder);
      case FormMetadata.fieldTypeBirthDate:
        field.title =
            Utilities.replaceIfNullOrEmpty(field.title, birthDateLabel());
        return BirthDateFieldBuilder.buildBirthDateField(
          context: context,
          formHolder: formHolder,
          fieldHolder: field as BirthDateFieldHolder,
          formKey: formHolder.controller!.globalKey,
        );
      case FormMetadata.fieldTypeIdDocument:
        field.title =
            Utilities.replaceIfNullOrEmpty(field.title, idDocumentLabel());
        return IdDocumentFieldBuilder.buildIdDocumentField(
          context: context,
          fieldHolder: field as IdDocumentFieldHolder,
          formKey: formHolder.controller!.globalKey,
          formHolder: formHolder,
        );
      case FormMetadata.fieldTypeBirthYear:
        field.title =
            Utilities.replaceIfNullOrEmpty(field.title, birthYearLabel());
        return FormFieldBuilders.buildBirthYearField(
            context, formHolder, field);
      case FormMetadata.fieldTypeTicket:
        var ticketHolder = field as TicketHolder;
        return FormFieldBuilders.buildTicketField(
            context, formHolder, ticketHolder);
      default:
        return const SizedBox.shrink();
    }
  }

  static Map<String, dynamic> replaceSpotWithId(
      Map<String, dynamic> inputData) {
    if (inputData.containsKey(FormMetadata.fieldTypeTicket) &&
        inputData[FormMetadata.fieldTypeTicket] is List) {
      List<dynamic> tickets = inputData[FormMetadata.fieldTypeTicket];
      for (int i = 0; i < tickets.length; i++) {
        var ticket = tickets[i];
        if (ticket is Map<String, dynamic> &&
            ticket.containsKey(FormMetadata.fieldTypeSpot)) {
          var spot = ticket[FormMetadata.fieldTypeSpot];
          if (spot is BlueprintObjectModel) {
            ticket[FormMetadata.fieldTypeSpot] = spot.id;
          }
        }
      }
    }
    return inputData;
  }

  static TextStyle labelTextStyle(BuildContext context) {
    return TextStyle(
      fontWeight: FontWeight.bold,
      color: ThemeConfig.grey700(context),
      fontSize: 19 * FormHelper.fontSizeFactor,
    );
  }

  static Widget buildLabel(BuildContext context, String label,
      {bool isRequired = false}) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          label,
          style: FormHelper.labelTextStyle(context),
        ),
        if (isRequired)
          Text(
            ' *',
            style: FormHelper.labelTextStyle(context).copyWith(
              color: ThemeConfig.redColor(context),
            ),
          ),
      ],
    );
  }

  static Widget buildCardWrapperDesign({
    required BuildContext context,
    required FieldHolder fieldHolder,
    required Widget content,
    bool hasError = false,
  }) {
    return Card(
      elevation: 0,
      margin: const EdgeInsets.symmetric(vertical: 4),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(8),
        side: hasError
            ? BorderSide(color: ThemeConfig.redColor(context), width: 1)
            : BorderSide.none,
      ),
      child: Padding(
        padding: const EdgeInsets.all(12.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Title for all
            buildLabel(context, fieldHolder.title ?? '',
                isRequired: fieldHolder.isRequired),
            // Optional description rendered via HtmlView if provided
            if (!HtmlHelper.isHtmlEmptyOrNull(fieldHolder.description))
              Column(
                children: [
                  HtmlView(
                    color: ThemeConfig.grey600(context),
                    html: fieldHolder.description!,
                    fontSize: optionDescriptionFontSize(),
                    isSelectable: true,
                  ),
                  SizedBox.square(dimension: 12)
                ],
              ),
            // Widget content that fills remaining space
            content,
          ],
        ),
      ),
    );
  }

  /// Convenience to match the description style size.
  static double optionDescriptionFontSize() {
    return 13.0 * FormHelper.fontSizeFactor;
  }

  /// Text style used for option titles in checkboxes/radios.
  static TextStyle cardOptionTitleTextStyle() {
    return TextStyle(
        fontSize: 15.0 * FormHelper.fontSizeFactor,
        fontWeight: FontWeight.w400);
  }

  // Modify buildInputDecoration to optionally wrap the label
  static InputDecoration buildInputDecoration({
    required BuildContext context,
    required String label,
    required bool isRequired,
  }) {
    return InputDecoration(
      filled: true,
      fillColor: Colors.transparent,
      border: InputBorder.none,
      label: Text.rich(
        TextSpan(
          text: label,
          style: FormHelper.labelTextStyle(context),
          children: isRequired
              ? [
                  TextSpan(
                    text: ' *',
                    style: FormHelper.labelTextStyle(context).copyWith(
                      color: ThemeConfig.redColor(context),
                    ),
                  )
                ]
              : [],
        ),
        softWrap: true,
      ),
    );
  }

  static bool anyHasDescription(List<FormOptionDefinition> options) {
    return options
        .any((option) => !HtmlHelper.isHtmlEmptyOrNull(option.description));
  }

  static bool isCardDesign(FormHolder formHolder, FieldHolder field) {
    if (formHolder.isCardDesign == true) {
      return true;
    }
    if (field is OptionsFieldHolder) {
      if (anyHasDescription(field.options)) {
        return true;
      }
    }
    return !HtmlHelper.isHtmlEmptyOrNull(field.description);
  }

  static Widget htmlDescription(String? description) {
    if (HtmlHelper.isHtmlEmptyOrNull(description)) {
      return SizedBox.shrink();
    }
    return HtmlView(
      html: description!,
      fontSize: 14,
      isSelectable: true,
    );
  }
}
