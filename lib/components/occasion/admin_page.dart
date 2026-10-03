import 'package:fstapp/components/navigation/administration_loading_shell.dart';
import 'package:fstapp/data_services/rights_service.dart';
import 'package:auto_route/auto_route.dart';
import 'package:flutter/material.dart';
import 'package:fstapp/components/navigation/routed_tab_scaffold.dart';
import 'package:fstapp/components/navigation/occasion_administration_boundary.dart';
import 'package:fstapp/components/single_data_grid/admin_page_helper.dart';

@RoutePage()
class AdminPage extends StatelessWidget {
  static const ROUTE = 'admin';
  const AdminPage({super.key});
  @override
  Widget build(BuildContext context) {
    Localizations.localeOf(context);
    return OccasionAdministrationBoundary(
        reservations: false,
        loadingBuilder: (_) =>
            const AdministrationLoadingShell(reservations: false),
        // AutoRouter defers its initial routes until the next frame. Keep
        // the same chrome during that frame too, after access has resolved.
        builder: (_) => AutoRouter(
            placeholder: (_) =>
                const AdministrationLoadingShell(reservations: false)));
  }
}

@RoutePage()
class AdminTabsPage extends StatelessWidget {
  const AdminTabsPage({super.key});
  @override
  Widget build(BuildContext context) => ListenableBuilder(
      listenable: RightsService.occasionLinkModelNotifier,
      builder: (context, _) => _build(context));
  Widget _build(BuildContext context) {
    Localizations.localeOf(context);
    return RoutedTabScaffold(
        administration: true,
        reservations: false,
        tabs: AdministrationTabs.administration);
  }
}
