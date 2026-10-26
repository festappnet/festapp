import 'package:easy_localization/easy_localization.dart';

/// Localized strings for speakers (core) + the counseling feature.
/// Keys live under "FeatureCounseling" / "Speakers" / "Counseling" in
/// translations (cs + en only, permanently). Follows the namespaced
/// Strings-class pattern — never `'literal'.tr()` at call sites.
class SpeakersStrings {
  // Counseling feature metadata + config form ("Poradny").
  static String get counselingFeatureTitle => 'FeatureCounseling.title'.tr();
  static String get counselingFeatureDescription =>
      'FeatureCounseling.description'.tr();
  static String get counselingEventType =>
      'FeatureCounseling.counselingEventType'.tr(); // "Counseling event type code"
  static String get maxActiveBookings =>
      'FeatureCounseling.maxActiveBookings'.tr(); // "Max active reservations (0 = unlimited)"
  static String get registrationStartTime =>
      'FeatureCounseling.registrationStartTime'.tr();

  // Admin — speakers management
  static String get manageSpeakers => 'Speakers.manageSpeakers'.tr();
  static String get addSpeaker => 'Speakers.addSpeaker'.tr();
  static String get editSpeaker => 'Speakers.editSpeaker'.tr();
  static String get name => 'Speakers.name'.tr();
  static String get roleSubtitle => 'Speakers.roleSubtitle'.tr();
  static String get bio => 'Speakers.bio'.tr();
  static String get avatar => 'Speakers.avatar'.tr();
  static String get topics => 'Speakers.topics'.tr();
  static String get manageTopics => 'Speakers.manageTopics'.tr();
  static String get addTopic => 'Speakers.addTopic'.tr();
  static String get topicTitle => 'Speakers.topicTitle'.tr();
  static String get speakersOnEvent => 'Speakers.speakersOnEvent'.tr();
  static String get selectSpeakers => 'Speakers.selectSpeakers'.tr();
  static String get searchSpeakers => 'Speakers.searchSpeakers'.tr();
  static String get counselingSlots => 'Speakers.counselingSlots'.tr();
  static String get addSlot => 'Speakers.addSlot'.tr();
  static String get editSlot => 'Speakers.editSlot'.tr();
  static String get slotTooShort => 'Speakers.slotTooShort'.tr();
  static String get counselingEntryToggle =>
      'Speakers.counselingEntryToggle'.tr();
  static String get counselingEntryColumn =>
      'Speakers.counselingEntryColumn'.tr();

  // Admin — slot generator
  static String get generateSlots => 'Speakers.generateSlots'.tr();
  static String get slotFrom => 'Speakers.slotFrom'.tr();
  static String get slotTo => 'Speakers.slotTo'.tr();
  static String get slotLength => 'Speakers.slotLength'.tr();
  static String get slotBreak => 'Speakers.slotBreak'.tr();
  static String get slotCapacity => 'Speakers.slotCapacity'.tr();
  static String get slotPlace => 'Speakers.slotPlace'.tr();
  static String get deleteEmptySlots => 'Speakers.deleteEmptySlots'.tr();
  static String slotsCreated(int n) =>
      'Speakers.slotsCreated'.tr(namedArgs: {'count': '$n'});
  static String slotsDeleted(int n) =>
      'Speakers.slotsDeleted'.tr(namedArgs: {'count': '$n'});

  // User — counseling flow
  static String get counselingTitle => 'Counseling.title'.tr();
  static String get chooseArea => 'Counseling.chooseArea'.tr();
  static String get chooseAreaPrompt => 'Counseling.chooseAreaPrompt'.tr();
  static String get chooseCounselorAndTime =>
      'Counseling.chooseCounselorAndTime'.tr();
  static String get enterCounseling => 'Counseling.enterCounseling'.tr();
  static String get yourReservation => 'Counseling.yourReservation'.tr();
  static String get cancelReservation => 'Counseling.cancelReservation'.tr();
  static String get noCounselorsForArea =>
      'Counseling.noCounselorsForArea'.tr();
  static String get slotTaken => 'Counseling.slotTaken'.tr();
  static String get slotFree => 'Counseling.slotFree'.tr();
  static String get reserved => 'Counseling.reserved'.tr();
  static String get signUp => 'Counseling.signUp'.tr();
  static String get signInToReserve => 'Counseling.signInToReserve'.tr();
  static String get lecturers => 'Speakers.lecturers'.tr(); // section title on event page

  /// Message for the counseling booking limit (sign_user_to_event code 109).
  static String get bookingLimitReached =>
      'Counseling.bookingLimitReached'.tr();
}
