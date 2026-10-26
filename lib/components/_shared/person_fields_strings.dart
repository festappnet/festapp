import 'package:easy_localization/easy_localization.dart';

/// Localized strings for person-related form fields shared across components.
/// Keys live under the "PersonFields" namespace in assets/translations/*.json.
class PersonFieldsStrings {
  static String get address => 'PersonFields.address'.tr(); // "Address"
  static String get birthDate => 'PersonFields.birthDate'.tr(); // "Birth Date"
  static String get birthYear => 'PersonFields.birthYear'.tr(); // "Birth year"
  static String get city => 'PersonFields.city'.tr(); // "City"
  static String get email => 'PersonFields.email'.tr(); // "E-mail"
  static String get emailInvalid =>
      'PersonFields.emailInvalid'.tr(); // "E-mail is not valid!"
  static String get expiryDate =>
      'PersonFields.expiryDate'.tr(); // "Expiry Date"
  static String get expiryDateInPast => 'PersonFields.expiryDateInPast'
      .tr(); // "Expiry date cannot be in the past."
  static String get female => 'PersonFields.female'.tr(); // "Female"
  static String get male => 'PersonFields.male'.tr(); // "Male"
  static String get sexLabel => 'PersonFields.sexLabel'.tr(); // "I am"
  static String get notSpecified =>
      'PersonFields.notSpecified'.tr(); // "Not specified"
  static String get nationality =>
      'PersonFields.nationality'.tr(); // "Nationality"
  static String get phone => 'PersonFields.phone'.tr(); // "Phone"
  static String get surname => 'PersonFields.surname'.tr(); // "Surname"
  static String get identificationDocument => 'PersonFields.identificationDocument'
      .tr(); // "Identification document"
  static String ageOutsideRecommendedRange(
          {required String minAge, required String maxAge}) =>
      'PersonFields.ageOutsideRecommendedRange'.tr(namedArgs: {
        'minAge': minAge,
        'maxAge': maxAge
      }); // "Warning: Your age is not within the recommended range ({minAge}-{maxAge} years old)."
  static String ageRestriction(
          {required String minAge, required String maxAge}) =>
      'PersonFields.ageRestriction'.tr(namedArgs: {
        'minAge': minAge,
        'maxAge': maxAge
      }); // "You must be between {minAge} and {maxAge} years old."
}
