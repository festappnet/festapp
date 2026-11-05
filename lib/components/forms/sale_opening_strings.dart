import 'package:easy_localization/easy_localization.dart';

class SaleOpeningStrings {
  static String configuredStart(String date) =>
      'SaleOpening.configuredStart'.tr(namedArgs: {'date': date});
  static String scheduledStart(String date) =>
      'SaleOpening.scheduledStart'.tr(namedArgs: {'date': date});
  static String subscribed(String email) =>
      'SaleOpening.subscribed'.tr(namedArgs: {'email': email});
  static String get notifyShort => 'SaleOpening.notifyShort'.tr();
  static String text(String key, {bool informal = false}) =>
      'SaleOpening.$key${informal ? 'Informal' : ''}'.tr();
  static String get titleRegistration => 'SaleOpening.titleRegistration'.tr();
  static String get title => 'SaleOpening.title'.tr();
  static String get enable => 'SaleOpening.enable'.tr();
  static String get explanation => 'SaleOpening.explanation'.tr();
  static String get disclaimer => 'SaleOpening.disclaimer'.tr();
  static String get email => 'SaleOpening.email'.tr();
  static String get subscribe => 'SaleOpening.subscribe'.tr();
  static String get unsubscribe => 'SaleOpening.unsubscribe'.tr();
  static String get unsubscribed => 'SaleOpening.unsubscribed'.tr();
  static String get invalid => 'SaleOpening.invalid'.tr();
  static String get failed => 'SaleOpening.failed'.tr();
  static String get tryLater => 'SaleOpening.tryLater'.tr();
  static String get pause => 'SaleOpening.pause'.tr();
  static String get end => 'SaleOpening.end'.tr();
  static String get subscribers => 'SaleOpening.subscribers'.tr();
  static String get requiresStart => 'SaleOpening.requiresStart'.tr();
  static String get dateChange => 'SaleOpening.dateChange'.tr();
  static String get editEmails => 'SaleOpening.editEmails'.tr();
  static String get active => 'SaleOpening.active'.tr();
  static String get closed => 'SaleOpening.closed'.tr();
  static String get queued => 'SaleOpening.queued'.tr();
  static String get accepted => 'SaleOpening.accepted'.tr();
  static String get delivered => 'SaleOpening.delivered'.tr();
  static String get error => 'SaleOpening.error'.tr();
  static String get paused => 'SaleOpening.paused'.tr();
  static String get endConfirm => 'SaleOpening.endConfirm'.tr();
}
