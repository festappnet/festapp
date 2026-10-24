import 'package:flutter/foundation.dart';
import 'email_delivery_strings.dart';

/// The server chooses current issues; all order surfaces share this classifier.
class OrderEmailIssue {
  static final changes = ValueNotifier<int>(0);
  OrderEmailIssue(this.data);
  final Map<String, dynamic> data;
  static List<OrderEmailIssue> fromSummary(Map<String, dynamic>? summary) =>
      ((summary?['current_issues'] as List?) ?? const [])
          .map((e) => OrderEmailIssue(Map<String, dynamic>.from(e as Map)))
          .toList();
  static bool needsAttention(String state) => const {
        'retry_wait',
        'unknown',
        'dead',
        'bounce',
        'complaint',
        'suppressed',
        'reject',
        'rendering_failure',
        'delay',
        'post_action_failed',
        'blocked',
      }.contains(state);
  String get sourceId => data['source_message_id'].toString();
  String get messageId => data['message_id'].toString();
  String get kind => data['kind'].toString();
  String get state => data['state'].toString();
  String get originalRecipient => data['original_recipient']?.toString() ?? '';
  String get recipient {
    final current = data['recipient']?.toString().trim() ?? '';
    return current.isNotEmpty ? current : originalRecipient.trim();
  }
  bool get uncertain => state == 'unknown' || state == 'sending';
  bool get isFailure =>
      const {
        'bounce',
        'complaint',
        'reject',
        'rendering_failure',
        'dead',
        'suppressed',
        'post_action_failed'
      }.contains(state) &&
      data['resolution'] != 'waiting_repair' &&
      data['resolution'] != 'cancelled';
  bool blocksRecipient(String email) =>
      (data['suppression_reason'] != null ||
          state == 'complaint' ||
          state == 'suppressed') &&
      email.trim().toLowerCase() ==
          (data['recipient'] ?? originalRecipient).toString().toLowerCase();
  String? get reasonDescription =>
      switch (data['suppression_reason'] ?? data['reason']) {
        'complaint' => EmailDeliveryStrings.recovery('spam'),
        'hard_bounce' => EmailDeliveryStrings.recovery('hardBounce'),
        'queue_paused' => EmailDeliveryStrings.recovery('paused'),
        'queue_limit' ||
        'capacity_deferred' ||
        'recipient_deferred' ||
        'throttled' =>
          EmailDeliveryStrings.recovery('limited'),
        'lease_expired' ||
        'sender_ambiguous' =>
          EmailDeliveryStrings.recovery('uncertain'),
        _ => null,
      };
  bool get canResend =>
      !uncertain &&
      !const {'pending', 'preparing', 'blocked'}.contains(state) &&
      state != 'post_action_failed' &&
      data['obsolete'] != true &&
      data['resolution'] != 'cancelled' &&
      data['resolution'] != 'waiting_repair';
  String get description => _description();
  String get tooltipDescription => _description(includeRecipient: true);

  String _description({bool includeRecipient = false}) {
    final status = switch (data['resolution']) {
      'cancelled' => EmailDeliveryStrings.recovery('cancelled'),
      'waiting_repair' => EmailDeliveryStrings.recovery('waiting'),
      'stale_delivery' => EmailDeliveryStrings.recovery('staleDelivery'),
      _ => EmailDeliveryStrings.state(state),
    };
    return '${EmailDeliveryStrings.kind(kind)}${!includeRecipient || recipient.isEmpty ? '' : ' ($recipient)'}: $status';
  }
}
