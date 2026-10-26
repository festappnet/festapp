import 'help_occasion_picker.dart';

import 'package:fstapp/components/unit/db_units.dart';
import 'package:fstapp/components/unit/unit_model.dart';
import 'package:fstapp/components/unit/unit_creation_helper.dart';
import 'package:fstapp/components/occasion/occasion_creation_helper.dart';
import 'package:fstapp/components/occasion/setup/occasion_setup_page.dart';
import 'package:fstapp/data_services/authorization_capabilities.dart';

import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:material_ui/material_ui.dart';
import 'package:fstapp/app_config.dart';
import 'package:fstapp/components/occasion/db_occasions.dart';
import 'package:fstapp/components/occasion/occasion_model.dart';
import 'package:fstapp/components/_shared/common_strings.dart';
import 'package:fstapp/data_services/rights_service.dart';
import 'package:fstapp/services/last_administration_context.dart';
import 'package:fstapp/widgets/app_dialog.dart';

/// Reuses permission-filtered organizer data. Neither local storage nor a help
/// link grants access. The caller reloads the chosen context before routing.
enum _HelpChoice { create }

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
        for (final occasion in await DbOccasions.getAllOccasionsForEdit(
          unit.id!,
        )) {
          occasion.unit ??= unit.id;
          add(occasion);
        }
      } on PostgrestException catch (error) {
        // A unit membership need not grant catalog discovery. Keep the events
        // independently returned for this actor; other errors remain retryable.
        if (error.code != '42501') rethrow;
      }
    }
  }
  // Keep freshly fetched organizer/date metadata when the same event is open.
  if (selected != null && !candidates.containsKey(selected.link)) add(selected);
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
  final preferred =
      selected?.link ??
      (remembered == null ? null : Uri.parse(remembered).pathSegments.first);
  if (!context.mounted || RightsService.currentUser()?.id != user?.id) {
    return null;
  }
  // Always show the chosen event explicitly. A help page opened in another tab
  // must not silently apply a stale event preference to a different task.
  Object? pendingChoice;
  final choice = await showDialog<Object>(
    context: context,
    builder: (dialogContext) => AppAlertDialog(
      title: Text('HelpNavigation.chooseEvent'.tr()),
      content: SizedBox(
        width: 480,
        height:
            ((MediaQuery.sizeOf(dialogContext).height -
                        MediaQuery.viewInsetsOf(dialogContext).bottom) *
                    .6)
                .clamp(0, 480)
                .toDouble(),
        child: HelpOccasionPicker(
          occasions: candidates.values.toList(),
          organizers: [...?user?.units, ?RightsService.currentUnit()],
          selectedLink: selected?.link,
          recentLink: preferred,
          onSelected: (occasion) => pendingChoice = occasion.link,
          onCreateNew: () => pendingChoice = _HelpChoice.create,
          onDismiss: () => Navigator.of(dialogContext).pop(pendingChoice),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(dialogContext).pop(),
          child: Text(CommonStrings.cancel),
        ),
      ],
    ),
  );
  if (!context.mounted || RightsService.currentUser()?.id != user?.id)
    return null;
  if (choice is String) return choice;
  if (choice != _HelpChoice.create) return null;
  final created = await _createHelpOccasion(context);
  if (created != null) return created;
  // A cancelled wizard keeps its saved draft and the original help URL.
  if (!context.mounted || RightsService.currentUser()?.id != user?.id)
    return null;
  return chooseHelpOccasion(context);
}

/// Organization tasks must not select an event or create an event draft.
Future<int?> chooseHelpOrganization(BuildContext context) async {
  final userId = RightsService.currentUser()?.id;
  final units = RightsService.currentUser()?.units ?? <UnitModel>[];
  if (units.isEmpty) {
    if (RightsService.occasionLinkModel?.organization?.isUnitCreationEnabled !=
        true) {
      await showHelpAccess(context, organization: true);
      return null;
    }
    final created = await UnitCreationHelper.createNewUnit(context);
    return context.mounted && RightsService.currentUser()?.id == userId
        ? created?.id
        : null;
  }
  if (units.length == 1) return units.single.id;
  final unit = await showDialog<UnitModel>(
    context: context,
    builder: (dialogContext) => AppAlertDialog(
      title: Text('HelpNavigation.openOrganizer'.tr()),
      content: SizedBox(
        width: 480,
        child: ListView(
          shrinkWrap: true,
          children: units
              .map(
                (unit) => ListTile(
                  title: Text(unit.title ?? '${unit.id}'),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () => Navigator.of(dialogContext).pop(unit),
                ),
              )
              .toList(),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(dialogContext).pop(),
          child: Text(CommonStrings.cancel),
        ),
      ],
    ),
  );
  return context.mounted && RightsService.currentUser()?.id == userId
      ? unit?.id
      : null;
}

Future<String?> _createHelpOccasion(BuildContext context) async {
  final units = RightsService.currentUser()?.units ?? <UnitModel>[];
  UnitModel? unit;
  if (units.isEmpty) {
    if (RightsService.occasionLinkModel?.organization?.isUnitCreationEnabled !=
        true) {
      await showHelpAccess(context);
      return null;
    }
    unit = await UnitCreationHelper.createNewUnit(context);
  } else if (units.length == 1) {
    unit = units.single;
  } else {
    unit = await showDialog<UnitModel>(
      context: context,
      builder: (dialogContext) => AppAlertDialog(
        title: Text('HelpNavigation.chooseOrganizer'.tr()),
        content: SizedBox(
          width: 480,
          child: ListView(
            shrinkWrap: true,
            children: units
                .map(
                  (unit) => ListTile(
                    title: Text(unit.title ?? '${unit.id}'),
                    trailing: const Icon(Icons.chevron_right),
                    onTap: () => Navigator.of(dialogContext).pop(unit),
                  ),
                )
                .toList(),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: Text(CommonStrings.cancel),
          ),
        ],
      ),
    );
  }
  if (unit?.id == null || !context.mounted) return null;
  // Consume the server's current unit capability, never infer create access
  // from a remembered membership or a role combination.
  await RightsService.updateAppData(
    unitId: unit!.id,
    force: true,
    refreshOffline: false,
  );
  if (!context.mounted) return null;
  if (RightsService.currentUnit()?.id != unit.id ||
      !RightsService.hasCapability(AuthorizationCapabilities.occasionsCreate)) {
    await showHelpAccess(context);
    return null;
  }
  final dashboard = await DbUnits.getOccasionDashboard(unit.id!);
  if (!context.mounted) return null;
  if (AppConfig.occasionSetupEnabled && dashboard.drafts.isNotEmpty) {
    // Reloading a help link must offer the real saved wizard before creating
    // another draft. Finalization still uses the normal permission-checked RPC.
    final draft = await showDialog<Object>(
      context: context,
      builder: (dialogContext) => AppAlertDialog(
        title: Text('HelpNavigation.resumeSetup'.tr()),
        content: SizedBox(
          width: 480,
          child: ListView(
            shrinkWrap: true,
            children: dashboard.drafts
                .map(
                  (draft) => ListTile(
                    title: Text(
                      draft.title.isEmpty
                          ? 'HelpNavigation.untitledEvent'.tr()
                          : draft.title,
                    ),
                    trailing: const Icon(Icons.chevron_right),
                    onTap: () => Navigator.of(dialogContext).pop(draft),
                  ),
                )
                .toList(),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: Text(CommonStrings.cancel),
          ),
          TextButton(
            onPressed: () =>
                Navigator.of(dialogContext).pop(_HelpChoice.create),
            child: Text('HelpNavigation.createEvent'.tr()),
          ),
        ],
      ),
    );
    if (draft == null || !context.mounted) return null;
    if (draft != _HelpChoice.create) {
      final selected = dashboard.drafts.firstWhere(
        (item) => identical(item, draft),
      );
      final result = await OccasionSetupPage.open(
        context,
        selected,
        showCompletion: false,
      );
      return result?.link;
    }
  }
  final created = await OccasionCreationHelper.createNewOccasion(
    context,
    unit,
    dashboard.occasions,
    showCompletion: false,
  );
  return created?.link;
}

Future<void> showHelpAccess(
  BuildContext context, {
  bool organization = false,
}) => showDialog<void>(
  context: context,
  builder: (dialogContext) => AppAlertDialog(
    title: Text(
      (organization
              ? 'HelpNavigation.organizationAccess'
              : 'HelpNavigation.createEvent')
          .tr(),
    ),
    content: Text(
      (organization
              ? 'HelpNavigation.noOrganizationAccess'
              : 'HelpNavigation.noCreateAccess')
          .tr(),
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.of(dialogContext).pop(),
        child: Text(CommonStrings.cancel),
      ),
    ],
  ),
);
