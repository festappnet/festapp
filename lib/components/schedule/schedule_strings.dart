import 'package:easy_localization/easy_localization.dart';

/// Localized strings for the schedule and timeline components.
/// Keys live under the "FeatureSchedule" namespace in assets/translations/*.json.
class ScheduleStrings {
  // --- Schedule pages & timeline ---
  static String get exclusivity =>
      'FeatureSchedule.exclusivity'.tr(); // "Exclusivity"
  static String get suspiciousEvents =>
      'FeatureSchedule.suspiciousEvents'.tr(); // "Suspicious events"
  static String get suspiciousEventsDescription =>
      'FeatureSchedule.suspiciousEventsDescription'.tr();
  static String get suspiciousReason => 'FeatureSchedule.suspiciousReason'.tr();
  static String get suspiciousReasonInvalidTiming =>
      'FeatureSchedule.suspiciousReasonInvalidTiming'.tr();
  static String get suspiciousReasonMultiDay =>
      'FeatureSchedule.suspiciousReasonMultiDay'.tr();
  static String get suspiciousReasonOutsideOccasion =>
      'FeatureSchedule.suspiciousReasonOutsideOccasion'.tr();
  static String get suspiciousReasonExactDuplicate =>
      'FeatureSchedule.suspiciousReasonExactDuplicate'.tr();
  static String suspiciousReasonInvalidTimingDetail({
    required String start,
    required String end,
  }) =>
      'FeatureSchedule.suspiciousReasonInvalidTimingDetail'
          .tr(namedArgs: {'start': start, 'end': end});
  static String suspiciousReasonMultiDayDetail({
    required String start,
    required String end,
  }) =>
      'FeatureSchedule.suspiciousReasonMultiDayDetail'
          .tr(namedArgs: {'start': start, 'end': end});
  static String suspiciousReasonOutsideOccasionDetail({
    required String eventRange,
    required String occasionRange,
  }) =>
      'FeatureSchedule.suspiciousReasonOutsideOccasionDetail'.tr(namedArgs: {
        'eventRange': eventRange,
        'occasionRange': occasionRange,
      });
  static String suspiciousReasonExactDuplicateDetail({
    required String title,
    required String time,
    required String place,
  }) =>
      'FeatureSchedule.suspiciousReasonExactDuplicateDetail'.tr(namedArgs: {
        'title': title,
        'time': time,
        'place': place,
      });
  static String get profile => 'FeatureUser.profile'.tr(); // "Profile"
  static String get noEvents => 'FeatureSchedule.noEvents'.tr(); // "No events"
  static String get today => 'FeatureSchedule.today'.tr(); // "Today"
  static String get addToSchedule =>
      'FeatureSchedule.addToSchedule'.tr(); // "Add To Schedule"
  static String get rightNow => 'FeatureSchedule.rightNow'.tr(); // "Right Now"
  static String get ended => 'FeatureSchedule.ended'.tr(); // "Ended"
  static String get afternoon =>
      'FeatureSchedule.afternoon'.tr(); // "Afternoon"
  static String get evening => 'FeatureSchedule.evening'.tr(); // "Evening"
  static String get scan => 'FeatureSchedule.scan'.tr(); // "Scan"
  static String get initializing =>
      'FeatureSchedule.initializing'.tr(); // "Initializing..."
  static String get myScheduleEmpty => 'FeatureSchedule.myScheduleEmpty'
      .tr(); // "There will appear your events."

  // --- Schedule datagrid (admin) ---
  static String get interest => 'FeatureSchedule.interest'.tr(); // "Interest"
  static String get introImage =>
      'FeatureSchedule.introImage'.tr(); // "Intro Image"
  static String get imageUploaded =>
      'FeatureSchedule.imageUploaded'.tr(); // "Image uploaded successfully"
  static String get imageRemoved =>
      'FeatureSchedule.imageRemoved'.tr(); // "Image removed"
  static String get group => 'FeatureSchedule.group'.tr(); // "Group"
  static String get splitMenWomen =>
      'FeatureSchedule.splitMenWomen'.tr(); // "M/F 50/50"
  static String get showInsideEvent =>
      'FeatureSchedule.showInsideEvent'.tr(); // "Show inside event"
  static String get roles => 'FeatureSchedule.roles'.tr(); // "Roles"
  static String get selectEvents =>
      'FeatureSchedule.selectEvents'.tr(); // "Select events"
  static String get searchEvents =>
      'FeatureSchedule.searchEvents'.tr(); // "Search events"

  // --- Event edit ---
  static String get deleteEventConfirm => 'FeatureSchedule.deleteEventConfirm'
      .tr(); // "Are you sure you want to delete this event?"
  static String get maxParticipants =>
      'FeatureSchedule.maxParticipants'.tr(); // "Maximum of participants"

  // --- Event page ---
  static String get accountRequiredToJoin =>
      'FeatureSchedule.accountRequiredToJoin'
          .tr(); // "An account is required to join this event."
  static String get clickHereToSignIn =>
      'FeatureSchedule.clickHereToSignIn'.tr(); // "Click here to sign in."
  static String get eventFullyBooked =>
      'FeatureSchedule.eventFullyBooked'.tr(); // "This event is fully booked."
  static String get moderator =>
      'FeatureSchedule.moderator'.tr(); // "Moderator"
  static String get participantsCopied => 'FeatureSchedule.participantsCopied'
      .tr(); // "Participants have been copied."
  static String get signInOther =>
      'FeatureSchedule.signInOther'.tr(); // "Sign in other"
  static String get signInSomeone =>
      'FeatureSchedule.signInSomeone'.tr(); // "Sign in"
  static String get signOutParticipant =>
      'FeatureSchedule.signOutParticipant'.tr(); // "Sign out participant"
  static String signOutParticipantConfirm(
          {required String participant, required String event}) =>
      'FeatureSchedule.signOutParticipantConfirm'.tr(namedArgs: {
        'participant': participant,
        'event': event
      }); // "Do you want to sign out participant {participant} from {event}?"
  static String get signOutSomeone =>
      'FeatureSchedule.signOutSomeone'.tr(); // "Sign out someone"

  // --- My schedule ---
  static String get addedToMySchedule =>
      'FeatureSchedule.addedToMySchedule'.tr(); // "Added to My schedule."
  static String get removedFromMySchedule =>
      'FeatureSchedule.removedFromMySchedule'
          .tr(); // "Removed from My schedule."
  static String get signInBeforeAddingToMySchedule =>
      'FeatureSchedule.signInBeforeAddingToMySchedule'
          .tr(); // "Before adding to 'My schedule', please sign in first."
  static String get programRemindersTitle =>
      'FeatureSchedule.programRemindersTitle'.tr();
  static String get programRemindersDescription =>
      'FeatureSchedule.programRemindersDescription'.tr();
  static String get programRemindersToggle =>
      'FeatureSchedule.programRemindersToggle'.tr();
  static String get programRemindersLeadTime =>
      'FeatureSchedule.programRemindersLeadTime'.tr();
  static String programRemindersMinutes(int minutes) =>
      'FeatureSchedule.programRemindersMinutes'
          .tr(namedArgs: {'minutes': minutes.toString()});

  // --- Event sign-in results ---
  static String get cannotSignIn =>
      'FeatureSchedule.cannotSignIn'.tr(); // "Cannot sign in!"
  static String get eventOver =>
      'FeatureSchedule.eventOver'.tr(); // "Event is over."
  static String get eventFull =>
      'FeatureSchedule.eventFull'.tr(); // "Event is full."
  static String get maxMenReached => 'FeatureSchedule.maxMenReached'
      .tr(); // "There is already the maximum of men."
  static String get maxWomenReached => 'FeatureSchedule.maxWomenReached'
      .tr(); // "There is already the maximum of women."
  static String get tooSoon =>
      'FeatureSchedule.tooSoon'.tr(); // "It's too soon!"
  static String signInFrom({required String time}) =>
      'FeatureSchedule.signInFrom'
          .tr(namedArgs: {'time': time}); // "You can sign in from {time}."
  static String get cannotSignOutPastEvent =>
      'FeatureSchedule.cannotSignOutPastEvent'
          .tr(); // "It is not possible to sign out from an event that has already taken place."

  // --- Gender-aware sign-in/out toasts ---
  // The JSON keys come in M/F variants; [genderPrefix] is "M" or "F"
  // (see UserInfoModel.getGenderPrefix). Anything else falls back to "M".

  static String youHaveBeenSignedIn(String? genderPrefix) =>
      (genderPrefix == 'F'
              ? 'FeatureSchedule.youHaveBeenSignedInF'
              : 'FeatureSchedule.youHaveBeenSignedInM')
          .tr(); // "You have been signed in."

  static String userHasBeenSignedIn(String? genderPrefix,
          {required String user}) =>
      (genderPrefix == 'F'
              ? 'FeatureSchedule.userHasBeenSignedInF'
              : 'FeatureSchedule.userHasBeenSignedInM')
          .tr(namedArgs: {'user': user}); // "{user} has been signed in."

  static String alreadySignedIn(String? genderPrefix) => (genderPrefix == 'F'
          ? 'FeatureSchedule.alreadySignedInF'
          : 'FeatureSchedule.alreadySignedInM')
      .tr(); // "You are already signed in."

  static String userAlreadySignedIn(String? genderPrefix,
          {required String user}) =>
      (genderPrefix == 'F'
              ? 'FeatureSchedule.userAlreadySignedInF'
              : 'FeatureSchedule.userAlreadySignedInM')
          .tr(namedArgs: {'user': user}); // "{user} is already signed in."

  static String alreadySignedInSameType(String? genderPrefix) =>
      (genderPrefix == 'F'
              ? 'FeatureSchedule.alreadySignedInSameTypeF'
              : 'FeatureSchedule.alreadySignedInSameTypeM')
          .tr(); // "You are already signed in at an event of this type."

  static String userAlreadySignedInSameType(String? genderPrefix,
          {required String user}) =>
      (genderPrefix == 'F'
              ? 'FeatureSchedule.userAlreadySignedInSameTypeF'
              : 'FeatureSchedule.userAlreadySignedInSameTypeM')
          .tr(namedArgs: {
        'user': user
      }); // "{user} is already signed in at an event of this type."

  static String alreadySignedInSameTime(String? genderPrefix) => (genderPrefix ==
              'F'
          ? 'FeatureSchedule.alreadySignedInSameTimeF'
          : 'FeatureSchedule.alreadySignedInSameTimeM')
      .tr(); // "You are already signed in at another event at the same time."

  static String userAlreadySignedInSameTime(String? genderPrefix,
          {required String user}) =>
      (genderPrefix == 'F'
              ? 'FeatureSchedule.userAlreadySignedInSameTimeF'
              : 'FeatureSchedule.userAlreadySignedInSameTimeM')
          .tr(namedArgs: {
        'user': user
      }); // "{user} is already signed in at another event at the same time."

  static String youHaveBeenSignedOut(String? genderPrefix) =>
      (genderPrefix == 'F'
              ? 'FeatureSchedule.youHaveBeenSignedOutF'
              : 'FeatureSchedule.youHaveBeenSignedOutM')
          .tr(); // "You have been signed out."

  static String userHasBeenSignedOut(String? genderPrefix,
          {required String user}) =>
      (genderPrefix == 'F'
              ? 'FeatureSchedule.userHasBeenSignedOutF'
              : 'FeatureSchedule.userHasBeenSignedOutM')
          .tr(namedArgs: {'user': user}); // "{user} has been signed out."
}
