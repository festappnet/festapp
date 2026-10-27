import 'package:festapp_core/eshop.dart' show formatCustomerLabel;
import 'package:fstapp/components/email_delivery/email_delivery_strings.dart';

import 'notification_center_controller.dart';
import 'notification_center_strings.dart';

/// Pure row presentation; transport identifiers never become visible labels.
class NotificationItemPresenter {
  NotificationItemPresenter(this.item, {this.locale});
  final String? locale;
  final NotificationItem item;
  bool get hasDetail =>
      (item.occasionLink != null && item.data['relatedOrders'] == true) ||
      item.data['messageId'] is String ||
      (item.occasionLink != null && item.data['orderId'] is int) ||
      (item.data['bankAccountId'] is int && item.data['unitId'] is int);
  bool get isError =>
      const {'email_problem', 'bank_problem'}.contains(item.kind) &&
      item.status != 'recovered';
  String get title => item.isSummary && (item.data['activityCount'] as int) > 1
      ? NotificationCenterStrings.activities(
          item.kind,
          item.data['activityCount'] as int,
          locale: locale,
        )
      : NotificationCenterStrings.kind(item.kind);
  String? get reason {
    final value = item.data['reason'];
    return value is String && value.isNotEmpty
        ? NotificationCenterStrings.reason(value)
        : null;
  }

  /// A bounded authorized preview, deduplicated without inventing customer counts.
  List<String> get previewNames {
    final contacts =
        item.data['previewContacts'] as List? ?? [item.data['contact']];
    return [
      for (final contact in contacts.whereType<Map>())
        formatCustomerLabel(
          name: contact['name'] as String?,
          surname: contact['surname'] as String?,
          email: contact['email'] as String?,
        ),
    ].where((name) => name.isNotEmpty).toSet().take(3).toList(growable: false);
  }

  List<String> get details {
    final data = item.data;
    final contact = data['contact'] as Map? ?? const {};
    final customer = formatCustomerLabel(
      name: contact['name'] as String?,
      surname: contact['surname'] as String?,
      email: contact['email'] as String?,
    );
    if (item.isSummary && (data['activityCount'] as int) > 1) {
      return [
        if (data['placeCount'] is int)
          NotificationCenterStrings.places(
            data['placeCount'] as int,
            locale: locale,
          ),
      ];
    }
    final count = data['count'] as int?;
    final multiple = (data['formContext'] as Map?)?['allowsMultiple'] == true;
    return [
      if (item.kind == 'email_problem' && data['recipient'] is String)
        data['recipient'] as String
      else if (customer.isNotEmpty)
        customer
      else if (item.kind == 'occasion_joined' && data['customerName'] is String)
        data['customerName'] as String,
      if (data['title'] is String &&
          (data['title'] as String).trim().isNotEmpty)
        (data['title'] as String).trim()
      else if (const {'form_opened', 'form_closed'}.contains(item.kind))
        NotificationCenterStrings.text('form'),
      if (count != null && (count > 1 || (count == 1 && multiple)))
        NotificationCenterStrings.places(count, locale: locale),
      if (data['messageKind'] is String)
        EmailDeliveryStrings.kind(data['messageKind']),
      if (reason != null) reason!,
      if (data['registrationMode'] == 'full')
        NotificationCenterStrings.kind('capacity_full'),
      if (data['registrationMode'] == 'waitlist')
        NotificationCenterStrings.text('acceptingWaitlist'),
      if (data['remainingPublic'] is int && data['limit'] is int)
        NotificationCenterStrings.capacity(
          data['remainingPublic'],
          data['limit'],
        ),
      if (data['heldForWaiting'] is int && data['heldForWaiting'] > 0)
        NotificationCenterStrings.held(data['heldForWaiting']),
      if (const {
            'capacity_full',
            'capacity_warning',
            'bank_problem',
            'email_problem',
          }.contains(item.kind) &&
          item.status == 'recovered')
        NotificationCenterStrings.status('recovered'),
    ].where((value) => value.isNotEmpty).toList();
  }
}
