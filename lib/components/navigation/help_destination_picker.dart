import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:fstapp/app_config.dart';
import 'package:fstapp/components/occasion/db_occasions.dart';
import 'package:fstapp/components/occasion/occasion_model.dart';
import 'package:fstapp/components/_shared/common_strings.dart';
import 'package:fstapp/data_services/rights_service.dart';
import 'package:fstapp/services/last_administration_context.dart';
import 'package:fstapp/widgets/app_dialog.dart';

/// Reuses permission-filtered organizer data. Neither local storage nor a help
/// link grants access. The caller reloads the chosen context before routing.
Future<String?> chooseHelpOccasion(BuildContext context) async {
  final user = RightsService.currentUser();
  final selected = RightsService.currentOccasion();
  final candidates = <String, OccasionModel>{};
  void add(OccasionModel occasion) {
    final link = occasion.link;
    if (link != null && RegExp(r'^[a-zA-Z0-9_-]+$').hasMatch(link)) {
      candidates[link] = occasion;
    }
  }

  for (final occasion in user?.occasions ?? <OccasionModel>[]) {
    add(occasion);
  }
  for (final unit in user?.units ?? []) {
    if (unit.id != null) {
      try {
        for (final occasion
            in await DbOccasions.getAllOccasionsForEdit(unit.id!)) {
          add(occasion);
        }
      } on PostgrestException catch (error) {
        // A unit membership need not grant catalog discovery. Keep the events
        // independently returned for this actor; other errors remain retryable.
        if (error.code != '42501') rethrow;
      }
    }
  }
  if (selected != null) add(selected);
  final remembered = await LastAdministrationContext.instance.restore(
    AppConfig.organization,
    user?.id,
    canAccess: (path) async {
      final parts = Uri.parse(path).pathSegments;
      return parts.first == 'unit'
          ? user?.units?.any((unit) => '${unit.id}' == parts[1]) == true
          : candidates.containsKey(parts.first);
    },
  );
  final preferred = selected?.link ??
      (remembered == null ? null : Uri.parse(remembered).pathSegments.first);
  if (!context.mounted || RightsService.currentUser()?.id != user?.id) {
    return null;
  }
  // Always show the chosen event explicitly. A help page opened in another tab
  // must not silently apply a stale event preference to a different task.
  return showDialog<String>(
      context: context,
      builder: (dialogContext) => AppAlertDialog(
            title: Text('HelpNavigation.chooseEvent'.tr()),
            content: SizedBox(
                width: 480,
                child: candidates.isEmpty
                    ? Text('HelpNavigation.noEvents'.tr())
                    : ListView(
                        shrinkWrap: true,
                        children: (candidates.values.toList()
                              ..sort((a, b) => a.link == b.link
                                  ? 0
                                  : a.link == preferred
                                      ? -1
                                      : b.link == preferred
                                          ? 1
                                          : (a.title ?? '')
                                              .compareTo(b.title ?? '')))
                            .map((occasion) => ListTile(
                                  title: Text(occasion.title ?? occasion.link!),
                                  subtitle: occasion.link == preferred
                                      ? Text('HelpNavigation.recentEvent'.tr())
                                      : null,
                                  trailing: const Icon(Icons.chevron_right),
                                  onTap: () => Navigator.of(dialogContext)
                                      .pop(occasion.link),
                                ))
                            .toList())),
            actions: [
              TextButton(
                  onPressed: () => Navigator.of(dialogContext).pop(),
                  child: Text(CommonStrings.cancel))
            ],
          ));
}
