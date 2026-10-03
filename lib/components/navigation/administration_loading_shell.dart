import 'package:auto_route/auto_route.dart';
import 'package:flutter/material.dart';
import 'package:fstapp/components/_shared/app_panel_helper.dart';
import 'package:fstapp/components/_shared/red_strip_widget.dart';
import 'package:fstapp/components/single_data_grid/admin_page_helper.dart';
import 'package:fstapp/data_services/rights_service.dart';

/// Preserve known navigation chrome while the new context/access check loads.
/// No destination content or data-grid controller is constructed here.
class AdministrationLoadingShell extends StatelessWidget {
  final bool reservations;
  final bool unit;
  const AdministrationLoadingShell(
      {super.key, this.reservations = false, this.unit = false});
  @override
  Widget build(BuildContext context) {
    if (RightsService.occasionLinkModel == null) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }
    final tabs = unit
        ? null
        : reservations
            ? AdministrationTabs.reservations
            : AdministrationTabs.administration;
    final active = context.router.root.currentSegments;
    final selected = tabs?.indexWhere((tab) =>
            active.any((route) => route.name == tab.route.routeName)) ??
        0;
    final scaffold = Scaffold(
        appBar:
            AppPanelHelper.buildAdaptiveAdminAppBar(context, activeTabs: tabs),
        body: const Center(child: CircularProgressIndicator()));
    final chrome = IgnorePointer(
        child: ExcludeFocus(
            child: DefaultTabController(
                length: tabs?.length ?? 0,
                initialIndex: selected < 0 ? 0 : selected,
                child: scaffold)));
    if (!reservations && !unit) return chrome;
    return Column(children: [
      const SafeArea(bottom: false, child: RedStripWidget()),
      Expanded(child: chrome),
    ]);
  }
}
