import 'package:easy_localization/easy_localization.dart';
import 'package:fstapp/components/blueprint/blueprint_seat.dart';
import 'package:fstapp/components/forms/models/form_option_model.dart';
import 'package:fstapp/components/users/user_info_model.dart';
import 'package:flutter/material.dart';
import 'package:flutter_form_builder/flutter_form_builder.dart';
import 'package:fstapp/components/blueprint/blueprint_object_model.dart';
import 'package:fstapp/widgets/standard_dialog.dart';
import 'package:fstapp/components/eshop/orders_strings.dart';
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
  static const String fieldTypeName = "name";
  static const String fieldTypeSurname = "surname";
  static const String fieldTypeCity = "city";
  static const String fieldTypeEmail = "email";
  static const String fieldTypePhone = "phone";
  static const String fieldTypeSex = "sex";
  static const String fieldTypeBirthYear = "birth_year";
  static const String fieldTypeNote = "note";
  static const String fieldTypeSpot = "spot";
  static const String fieldTypeText = "text";
  static const String fieldTypeSelectOne = "select_one";
  static const String fieldTypeSelectMany = "select_many";
  static const String fieldTypeProductType = "product_type";
  static const String fieldTypeBirthDate = "birth_date";
  static const String fieldTypeIdDocument = "id_document";
  static const String fieldTypeAddress = "address";
  static const String fieldTypeNationality = "nationality";
  static const String isGroupFeatureField = "is_group_feature";

  static const String fieldTypeTicket = "ticket";

  static const String optionDelimiter = " | ";

  static const String metaMaxTickets = "max_tickets";
  static const String metaSelectionType = "selection_type";
  static const String metaSelectionTypeMany = "select_many";
  static const String metaSelectionTypeOne = "select_one";
  static const String maxTickets = "max_tickets";

  static const String metaOptions = "options";
  static const String metaFields = "fields";
  static const String metaType = "type";
  static const String metaLabel = "label";
  static const String metaOptionsType = "optionsType";
  static const String metaSecret = "secret";
  static const String metaForm = "form";
  static const String metaEmpty = "---";
  static const String metaProducts = "products";
  static const String metaCommunicationTone = "communication_tone";
  static const String metaReplyTo = "reply_to";
  static const String metaDefaultValue = "default_value";

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

  static String ticketLabel() => OrdersStrings.itemSingular;
  static String textLabel() => FormStrings.textFieldType;
  static String selectOneLabel() => FormStrings.singleChoice;
  static String selectManyLabel() => FormStrings.multipleChoice;
  static String productTypeLabel() => FormStrings.productType;

  static const Map<String, IconData> fieldTypeIcons = {
    FormHelper.fieldTypeText: Icons.text_fields,
    FormHelper.fieldTypeSelectOne: Icons.radio_button_checked,
    FormHelper.fieldTypeSelectMany: Icons.check_box_outlined,
    FormHelper.fieldTypeEmail: Icons.email,
    FormHelper.fieldTypeName: Icons.person,
    FormHelper.fieldTypeSurname: Icons.person_outline,
    FormHelper.fieldTypeSex: Icons.wc,
    FormHelper.fieldTypeCity: Icons.location_city,
    FormHelper.fieldTypeAddress: Icons.home,
    FormHelper.fieldTypeNationality: Icons.flag,
    FormHelper.fieldTypeBirthYear: Icons.cake,
    FormHelper.fieldTypeBirthDate: Icons.cake,
    FormHelper.fieldTypeIdDocument: Icons.article,
    FormHelper.fieldTypeNote: Icons.note,
    FormHelper.fieldTypeSpot: Icons.event_seat,
    FormHelper.fieldTypeProductType: Icons.category,
    FormHelper.fieldTypeTicket: Icons.confirmation_number,
    FormHelper.fieldTypePhone: Icons.phone,
  };

  static const List<String> nonEditableFields = [
    fieldTypeSex,
    fieldTypeBirthYear,
    fieldTypeBirthDate,
    fieldTypeIdDocument,
    fieldTypeSelectMany,
    fieldTypeNote,
    fieldTypeSpot,
    fieldTypeProductType,
    fieldTypeTicket
  ];

  static const List<String> personalInfoFields = [
    fieldTypeName,
    fieldTypeSurname,
    fieldTypeCity,
    fieldTypeAddress,
    fieldTypeEmail,
    fieldTypePhone,
    fieldTypeSex,
    fieldTypeBirthYear,
    fieldTypeBirthDate,
    fieldTypeIdDocument,
    fieldTypeNationality,
  ];

  static bool isAlwaysRequired(String? type) {
    return const [
      fieldTypeEmail,
      fieldTypeTicket,
    ].contains(type);
  }

  static String fieldTypeToLocale(String fieldType) {
    switch (fieldType) {
      case fieldTypeName:
        return nameLabel();
      case fieldTypeSurname:
        return surnameLabel();
      case fieldTypeCity:
        return cityLabel();
      case fieldTypeAddress:
        return addressLabel();
      case fieldTypeNationality:
        return nationalityLabel();
      case fieldTypeEmail:
        return emailLabel();
      case fieldTypeSex:
        return sexLabel();
      case fieldTypeBirthYear:
        return birthYearLabel();
      case fieldTypeNote:
        return noteLabel();
      case fieldTypeSpot:
        return spotLabel();
      case fieldTypeTicket:
        return ticketLabel();
      case fieldTypeText:
        return textLabel();
      case fieldTypeSelectOne:
        return selectOneLabel();
      case fieldTypeSelectMany:
        return selectManyLabel();
      case fieldTypeProductType:
        return productTypeLabel();
      case fieldTypeBirthDate:
        return birthDateLabel();
      case fieldTypeIdDocument:
        return idDocumentLabel();
      case fieldTypePhone:
        return phoneLabel();
      default:
        return fieldType;
    }
  }

  static String fieldTypeValue(
      BuildContext context, String value, String? fieldType) {
    switch (fieldType) {
      case fieldTypeSex:
        return UserInfoModel.sexToLocale(value);
      case fieldTypeBirthDate:
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
      return true;
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
      if (k.fieldType == fieldTypeTicket) {
        toReturn[fieldTypeTicket] = value;
      } else {
        if (returnWithType == true) {
          if (toReturn[metaFields] == null) {
            toReturn[metaFields] = {};
          }
          toReturn[metaFields][k.fieldType] = value;
        } else {
          if (toReturn[metaFields] == null) {
            toReturn[metaFields] = [];
          }
          toReturn[metaFields].add({k.id.toString(): value});
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
      case fieldTypeSex:
        if (fieldValue == null) {
          return null;
        }
        return (fieldValue as FormOptionModel).id;
      case fieldTypeBirthYear:
        return (fieldValue != null && fieldValue.isNotEmpty)
            ? int.tryParse(fieldValue.toString())
            : null;
      case fieldTypeBirthDate:
        return (fieldValue is DateTime) ? fieldValue.toIso8601String() : null;
      case fieldTypeIdDocument:
        if (fieldHolder is IdDocumentFieldHolder) {
          return fieldHolder.getIdDocumentData(formKey);
        }
        return null;
      case fieldTypeSpot:
        if (fieldValue is BlueprintSeat) {
          return fieldValue.seat;
        }
        return null;
      case fieldTypeTicket:
        List<Map<String, dynamic>> tickets = [];
        var ticket = fieldHolder as TicketHolder;
        for (int i = 0; i < ticket.tickets.length; i++) {
          final ticketKey = ticket.tickets[i].ticketKey;
          if (ticketKey.currentState == null) continue;
          Map<String, dynamic> ticketData = {
            if (ticket.tickets[i].ticketId != null)
              'ticketId': ticket.tickets[i].ticketId,
          };
          for (var subFieldHolder in ticket.fields) {
            if (ticketData[metaFields] == null) {
              ticketData[metaFields] = [];
            }
            var value = getFieldData(ticketKey, subFieldHolder);
            if (subFieldHolder.fieldType == fieldTypeProductType &&
                (value == null || value == '')) {
              continue;
            }

            if (subFieldHolder.fieldType == fieldTypeProductType &&
                subFieldHolder is OptionsFieldProductHolder &&
                subFieldHolder.selectionType ==
                    OptionsFieldProductSelectionType.selectMany) {
              if (value is List) {
                // Ensure value is a list before iterating
                for (var v in value) {
                  ticketData[metaFields].add({subFieldHolder.fieldType: v});
                }
              }
            } else {
              ticketData[metaFields].add({
                subFieldHolder.fieldType: value,
                if (subFieldHolder.fieldType != fieldTypeProductType)
                  subFieldHolder.id.toString(): value,
              });
            }
          }
          if (ticket.tickets[i].seat != null) {
            ticketData[fieldTypeSpot] = ticket.tickets[i].seat!.seat;
          }
          tickets.add(ticketData);
        }
        return tickets;
      case fieldTypeSelectMany:
        if (fieldValue is List) {
          return fieldValue.map((e) {
            if (e is FormOptionModel) return e.title;
            return e.toString();
          }).join(optionDelimiter);
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
      case fieldTypeText:
        return FormFieldBuilders.buildTextField(context, formHolder, field, []);
      case fieldTypeNote:
        field.title = Utilities.replaceIfNullOrEmpty(field.title, noteLabel());
        return FormFieldBuilders.buildTextField(context, formHolder, field, []);
      case fieldTypeName:
        field.title = Utilities.replaceIfNullOrEmpty(field.title, nameLabel());
        return FormFieldBuilders.buildTextField(
            context, formHolder, field, [AutofillHints.givenName]);
      case fieldTypeSurname:
        field.title =
            Utilities.replaceIfNullOrEmpty(field.title, surnameLabel());
        return FormFieldBuilders.buildTextField(
            context, formHolder, field, [AutofillHints.familyName]);
      case fieldTypeCity:
        field.title = Utilities.replaceIfNullOrEmpty(field.title, cityLabel());
        return FormFieldBuilders.buildTextField(
            context, formHolder, field, [AutofillHints.addressCity]);
      case fieldTypeAddress:
        field.title =
            Utilities.replaceIfNullOrEmpty(field.title, addressLabel());
        return FormFieldBuilders.buildAddressField(context, formHolder, field);
      case fieldTypeNationality:
        field.title =
            Utilities.replaceIfNullOrEmpty(field.title, nationalityLabel());
        return FormFieldBuilders.buildNationalityField(
            context, formHolder, field);
      case fieldTypeSpot:
        field.title = Utilities.replaceIfNullOrEmpty(field.title, spotLabel());
        return FormFieldBuilders.buildSpotField(
            context, formKey, formHolder, field);
      case fieldTypeEmail:
        field.title = Utilities.replaceIfNullOrEmpty(field.title, emailLabel());
        return FormFieldBuilders.buildEmailField(context, formHolder, field);
      case fieldTypePhone:
        field.title = Utilities.replaceIfNullOrEmpty(field.title, phoneLabel());
        return FormFieldBuilders.buildPhoneNumber(context, formHolder, field);
      case fieldTypeSex:
        field.title = Utilities.replaceIfNullOrEmpty(field.title, sexLabel());
        var sexOptions = [
          FormOptionModel(UserInfoModel.sexes[0], maleLabel()),
          FormOptionModel(UserInfoModel.sexes[1], femaleLabel()),
        ];
        if (!isRequiredField) {
          sexOptions.insert(
              0, FormOptionModel(UserInfoModel.sexes[2], notSpecifiedLabel()));
        }
        return RadioFieldBuilder.buildRadioField(
            context, field, sexOptions, formHolder);
      case fieldTypeSelectOne:
        var optionsField = field as OptionsFieldHolder;
        return RadioFieldBuilder.buildRadioField(
            context, optionsField, optionsField.options, formHolder);
      case fieldTypeSelectMany:
        var optionsField = field as OptionsFieldHolder;
        return CheckboxFieldBuilder.buildSelectManyField(
            context, optionsField, optionsField.options, formHolder);
      case fieldTypeProductType:
        var optionsField = field as OptionsFieldProductHolder;
        if (optionsField.selectionType ==
            OptionsFieldProductSelectionType.selectMany) {
          return CheckboxFieldBuilder.buildSelectManyField(
              context, optionsField, optionsField.options, formHolder);
        }
        return RadioFieldBuilder.buildRadioField(
            context, optionsField, optionsField.options, formHolder);
      case fieldTypeBirthDate:
        field.title =
            Utilities.replaceIfNullOrEmpty(field.title, birthDateLabel());
        return BirthDateFieldBuilder.buildBirthDateField(
          context: context,
          formHolder: formHolder,
          fieldHolder: field as BirthDateFieldHolder,
          formKey: formHolder.controller!.globalKey,
        );
      case fieldTypeIdDocument:
        field.title =
            Utilities.replaceIfNullOrEmpty(field.title, idDocumentLabel());
        return IdDocumentFieldBuilder.buildIdDocumentField(
          context: context,
          fieldHolder: field as IdDocumentFieldHolder,
          formKey: formHolder.controller!.globalKey,
          formHolder: formHolder,
        );
      case fieldTypeBirthYear:
        field.title =
            Utilities.replaceIfNullOrEmpty(field.title, birthYearLabel());
        return FormFieldBuilders.buildBirthYearField(
            context, formHolder, field);
      case fieldTypeTicket:
        var ticketHolder = field as TicketHolder;
        return FormFieldBuilders.buildTicketField(
            context, formHolder, ticketHolder);
      default:
        return const SizedBox.shrink();
    }
  }

  static Map<String, dynamic> replaceSpotWithId(
      Map<String, dynamic> inputData) {
    if (inputData.containsKey(fieldTypeTicket) &&
        inputData[fieldTypeTicket] is List) {
      List<dynamic> tickets = inputData[fieldTypeTicket];
      for (int i = 0; i < tickets.length; i++) {
        var ticket = tickets[i];
        if (ticket is Map<String, dynamic> &&
            ticket.containsKey(fieldTypeSpot)) {
          var spot = ticket[fieldTypeSpot];
          if (spot is BlueprintObjectModel) {
            ticket[fieldTypeSpot] = spot.id;
          }
        }
      }
    }
    return inputData;
  }

  static Widget buildDescriptionButton(
      BuildContext context, String title, String description) {
    return TextButton(
      onPressed: () {
        showDialog(
          context: context,
          builder: (context) => StandardDialog(
            content: SingleChildScrollView(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    title,
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 8),
                  HtmlView(
                    html: description,
                    isSelectable: true,
                  ),
                ],
              ),
            ),
          ),
        );
      },
      child: Text(FormStrings.viewMore),
    );
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

  static bool anyHasDescription(List<FormOptionModel> options) {
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
