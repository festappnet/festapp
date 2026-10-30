import 'package:fstapp/components/forms/db_forms.dart';
import 'package:fstapp/components/forms/models/form_bundle.dart';

import 'notification_center_controller.dart';
import 'notification_item_presenter.dart';

import 'package:auto_route/auto_route.dart';
import 'package:flutter/widgets.dart';
import 'package:fstapp/components/navigation/root_route_navigation.dart';

/// Closing a selected modal consumes only its own query target. Retained editors
/// and unrelated query values stay in the existing native route stack.
Future<void> clearNotificationDetailTarget(
  BuildContext context,
  String parameter,
  String value, {
  Map<String, String> companions = const {},
}) async {
  final root = context.router.root;
  final uri = root.urlState.uri;
  if (uri.queryParameters[parameter] != value) return;
  final query = Map<String, List<String>>.of(uri.queryParametersAll)
    ..remove(parameter);
  for (final entry in companions.entries) {
    if (uri.queryParameters[entry.key] == entry.value) query.remove(entry.key);
  }
  final target = uri
      .replace(query: query.isEmpty ? '' : Uri(queryParameters: query).query)
      .toString();
  root.markUrlStateForReplace();
  await root.navigate(rootRouteForPath(root, target));
}

/// Resolve the stored identity against the current authorized occasion catalog.
/// Historical notification titles and links never select a different form.
Future<String?> notificationFormDetailPath(
  NotificationItem item, {
  Future<List<FormBundle>> Function(String)? loadForms,
}) async {
  if (!NotificationItemPresenter(item).hasFormDetail) return null;
  final forms = await (loadForms ?? DbForms.getAllFormsByOccasionLink)(
    item.occasionLink!,
  );
  for (final form in forms) {
    if (form.definition.id != item.data['formId']) continue;
    final link = form.definition.link;
    if (link == null || link.isEmpty) return null;
    return Uri(
      pathSegments: [
        '',
        item.occasionLink!,
        'reservations',
        'forms',
        link,
        'editor',
      ],
    ).toString();
  }
  return null;
}
