import 'package:easy_localization/easy_localization.dart';
import '../features/feature_constants.dart';
import '../features/feature_service.dart';

class WaitlistStrings {
  static String get offerReviewExplanation => text('offerReviewExplanation');
  static String get offerPlace => text('offerPlace');
  static String get offerTitle => text('offerTitle');
  static String get offerExplanation => text('offerExplanation');
  static String get offerContinue => text('offerContinue');
  static String get withdrawTitle => text('withdrawTitle');
  static String get withdrawSelectedTitle => text('withdrawSelectedTitle');
  static String get withdrawExplanation => text('withdrawExplanation');
  static String get declineOfferTitle => text('declineOfferTitle');
  static String get declineOfferExplanation => text('declineOfferExplanation');
  static String get cancelOfferTitle => text('cancelOfferTitle');
  static String get cancelOfferExplanation => text('cancelOfferExplanation');
  static String get refreshAfterMutation => text('refreshAfterMutation');
  static String text(String key) => 'Waitlist.$key'.tr();
  static String get formOpenWaitlistMessage => text('formOpenWaitlistMessage');
  static String get limitCapacity => text('limitCapacity');
  static String get limitTickets => text('limitTickets');
  static String get capacityHelp => text('capacityHelp');
  static String get capacityHelpLimited => text('capacityHelpLimited');
  static String get offeredPlacesCount => text('offeredPlacesCount');
  static String get waitlistOn => text('waitlistOn');
  static String get waitlistOff => text('waitlistOff');
  static String get waitlistHelp => text('waitlistHelp');
  static String get durationHelp => text('durationHelp');
  static String get blueprintCapacity => text('blueprintCapacity');
  static String get saveWithForm => text('saveWithForm');
  static String get applySettings => text('applySettings');
  static String get settings => text('settings');
  static String get capacity =>
      text(FeatureService.isFeatureEnabled(FeatureConstants.ticket)
          ? 'capacityTickets'
          : 'capacityRegistrations');
  static String get unlimited => text('unlimited');
  static String get enabled => text('enabled');
  static String get showRemaining => text('showRemaining');
  static String get durationHours => text('durationHours');
  static String get positiveNumber => text('positiveNumber');
  static String get activeEntries => text('activeEntries');
  static String get title => text('title');
  static String get explanation => text('explanation');
  static String get full => text('full');
  static String get registered => text('registered');
  static String get register => text('register');
  static String get accept => text('accept');
  static String get decline => text('decline');
  static String get withdraw => text('withdraw');
  static String get send => text('send');
  static String get expired => text('expired');
  static String get productAvailability => text('productAvailability');
  static String get selectPeople => text('selectPeople');
  static String get remaining => text('remaining');
  static String get confirm => text('confirm');
  static String get stale => text('stale');
  static String get queued => text('queued');
  static String get detail => text('detail');
  static String get offers => text('offers');
  static String get cancel => text('cancel');
  static String get linkedOrders => text('linkedOrders');
  static String get invalid => text('invalid');
  static String get refresh => text('refresh');
  static String get count => text('count');
  static String get expiresAt => text('expiresAt');
}
