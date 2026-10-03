import 'package:fstapp/components/navigation/administration_loading_shell.dart';
import 'package:fstapp/data_services/rights_service.dart';
import 'package:auto_route/auto_route.dart';
import 'package:flutter/material.dart';
import 'package:fstapp/components/navigation/routed_tab_scaffold.dart';
import 'package:fstapp/components/navigation/occasion_administration_boundary.dart';
import 'package:fstapp/components/single_data_grid/admin_page_helper.dart';

@RoutePage()
class ReservationsPage extends StatelessWidget {
  static const ROUTE = 'reservations';
  const ReservationsPage({super.key});
  @override
  Widget build(BuildContext context) {
    Localizations.localeOf(context);
    return OccasionAdministrationBoundary(
        reservations: true,
        loadingBuilder: (_) =>
            const AdministrationLoadingShell(reservations: true),
        // AutoRouter defers its initial routes until the next frame. Keep
        // the same chrome during that frame too, after access has resolved.
        builder: (_) => AutoRouter(
            placeholder: (_) =>
                const AdministrationLoadingShell(reservations: true)));
  }
}

@RoutePage()
class ReservationsTabsPage extends StatelessWidget {
  const ReservationsTabsPage({super.key});
  @override
  Widget build(BuildContext context) => ListenableBuilder(
      listenable: RightsService.occasionLinkModelNotifier,
      builder: (context, _) => _build(context));
  Widget _build(BuildContext context) {
    Localizations.localeOf(context);
    return RoutedTabScaffold(
        administration: true,
        reservations: true,
        tabs: AdministrationTabs.reservations);
  }
}
