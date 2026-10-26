import 'package:festapp_core/eshop.dart' show formatCustomerLabel;
import 'package:fstapp/components/email_delivery/email_delivery_strings.dart';

import 'notification_center_controller.dart';
import 'notification_center_strings.dart';

/// Pure row presentation; transport identifiers never become visible labels.
class NotificationItemPresenter {
  NotificationItemPresenter(this.item);
  final NotificationItem item;
  bool get hasDetail =>
      item.data['messageId'] is String ||
      (item.occasionLink != null && item.data['orderId'] is int) ||
      (item.data['bankAccountId'] is int && item.data['unitId'] is int);
  bool get isError =>
      const {'email_problem', 'bank_problem'}.contains(item.kind) &&
      item.status != 'recovered';
  String get title => NotificationCenterStrings.kind(item.kind);
  List<String> get details {
    final data = item.data;
    final contact = data['contact'] as Map? ?? const {};
    final customer = formatCustomerLabel(
      name: contact['name'] as String?,
      surname: contact['surname'] as String?,
      email: contact['email'] as String?,
    );
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
        NotificationCenterStrings.places(count),
      if (data['messageKind'] is String)
        EmailDeliveryStrings.kind(data['messageKind']),
      if (data['reason'] is String && (data['reason'] as String).isNotEmpty)
        NotificationCenterStrings.reason(data['reason']),
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
