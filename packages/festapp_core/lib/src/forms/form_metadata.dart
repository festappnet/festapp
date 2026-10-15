abstract final class FormMetadata {
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

  static const List<String> nonEditableFields = [
    fieldTypeSex,
    fieldTypeBirthYear,
    fieldTypeBirthDate,
    fieldTypeIdDocument,
    fieldTypeSelectMany,
    fieldTypeNote,
    fieldTypeSpot,
    fieldTypeProductType,
    fieldTypeTicket,
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
    return const [fieldTypeEmail, fieldTypeTicket].contains(type);
  }
}
