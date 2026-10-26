import 'package:easy_localization/easy_localization.dart';

class NotificationCenterStrings {
  static String text(String key) => 'NotificationCenter.$key'.tr();
  static String get title => text('title');
  static String kind(String kind) =>
      const {
        'occasion_joined',
        'event_capacity_full',
        'form_opened',
        'form_closed',
        'order_created',
        'waitlist_registered',
        'order_cancelled',
        'offer_accepted',
        'offer_declined',
        'offer_expired',
        'capacity_warning',
        'capacity_full',
        'capacity_reopened',
        'bank_problem',
        'email_problem',
      }.contains(kind)
      ? text('kinds.$kind')
      : title;
  static String status(String status) =>
      const {
        'membership_active',
        'membership_left',
        'active',
        'recovered',
        'resolved',
        'problem',
        'ordered',
        'paid',
        'sent',
        'storno',
        'cancelled',
        'waiting',
        'waitlisted',
        'offered',
        'accepted',
        'declined',
        'expired',
        'pending',
        'preparing_payment',
        'used',
      }.contains(status)
      ? text('states.$status')
      : '';
  static String reason(String value) =>
      const {
        'manual',
        'schedule_start',
        'schedule_end',
        'schedule_changed',
        'complaint',
        'bounce',
        'reject',
        'rendering_failure',
        'dead',
        'suppressed',
        'delayed',
        'post_action_failed',
        'fio_token_invalid_or_inactive',
        'fio_receiving_account_mismatch',
        'bank_sync_retry_required',
        'transport_unavailable',
        'stale_health',
      }.contains(value)
      ? text('reasons.$value')
      : text('needsAttention');
  static String places(int count) =>
      'NotificationCenter.places'.tr(namedArgs: {'count': '$count'});
  static String capacity(int remaining, int limit) =>
      'NotificationCenter.capacity'.tr(
        namedArgs: {'remaining': '$remaining', 'limit': '$limit'},
      );
  static String held(int count) =>
      'NotificationCenter.heldForWaiting'.tr(namedArgs: {'count': '$count'});
}
