import 'package:fstapp/components/navigation/navigation_paths.dart';
import 'package:flutter/material.dart';
import 'package:fstapp/components/email_delivery/email_delivery_strings.dart';
import 'package:fstapp/app_router.gr.dart';
import 'package:fstapp/app_config.dart';
import 'package:fstapp/components/features/feature_service.dart';
import 'package:fstapp/components/features/feature_constants.dart';
import 'package:fstapp/components/navigation/routed_tab_scaffold.dart';
import 'package:fstapp/components/eshop/orders_strings.dart';
import 'package:fstapp/components/forms/form_strings.dart';
import 'package:fstapp/components/inventory/views/inventory_strings.dart';
import 'package:fstapp/data_services/rights_service.dart';
import 'package:fstapp/components/email_templates/email_templates_strings.dart';
import 'package:fstapp/components/speakers/speakers_strings.dart';
import 'package:fstapp/components/single_data_grid/data_grid_strings.dart';
import 'package:fstapp/components/client_changes/client_changes_strings.dart';
import 'package:fstapp/components/_shared/common_strings.dart';

class AdministrationTabs {
  static RoutedTabDefinition get info => RoutedTabDefinition(
      slug: NavigationPaths.info,
      route: const InformationNavigationRoute(),
      label: DataGridStrings.tabInfo,
      icon: Icons.info);
  static RoutedTabDefinition get events => RoutedTabDefinition(
      slug: NavigationPaths.events,
      route: const ScheduleNavigationRoute(),
      label: CommonStrings.schedule,
      icon: Icons.calendar_month);
  static RoutedTabDefinition get places => RoutedTabDefinition(
      slug: NavigationPaths.places,
      route: const PlacesNavigationRoute(),
      label: CommonStrings.places,
      icon: Icons.pin_drop);
  static RoutedTabDefinition get speakers => RoutedTabDefinition(
      slug: NavigationPaths.speakers,
      route: const SpeakersSectionRoute(),
      label: SpeakersStrings.manageSpeakers,
      icon: Icons.record_voice_over);
  static RoutedTabDefinition get groups => RoutedTabDefinition(
      slug: NavigationPaths.groups,
      route: const GroupsSectionRoute(),
      label: CommonStrings.groups,
      icon: Icons.groups);
  static RoutedTabDefinition get service => RoutedTabDefinition(
      slug: NavigationPaths.services,
      route: const ServiceSectionRoute(),
      label: DataGridStrings.tabService,
      icon: Icons.food_bank);
  static RoutedTabDefinition get inventoryPools => RoutedTabDefinition(
      slug: NavigationPaths.inventoryPools,
      route: const InventoryPoolsNavigationRoute(),
      label: InventoryStrings.tabTitle,
      icon: Icons.view_module_outlined);
  static RoutedTabDefinition get volunteers => RoutedTabDefinition(
      slug: NavigationPaths.volunteers,
      route: const VolunteersSectionRoute(),
      label: CommonStrings.volunteers,
      icon: Icons.view_timeline);
  static RoutedTabDefinition get users => RoutedTabDefinition(
      slug: NavigationPaths.users,
      route: const UsersSectionRoute(),
      label: CommonStrings.users,
      icon: Icons.people);
  static RoutedTabDefinition get game => RoutedTabDefinition(
      slug: NavigationPaths.game,
      route: const GameNavigationRoute(),
      label: CommonStrings.game,
      icon: Icons.gamepad);
  static RoutedTabDefinition get form => RoutedTabDefinition(
      slug: NavigationPaths.forms,
      route: const FormsNavigationRoute(),
      label: FormStrings.formsTitle,
      icon: Icons.list);
  static RoutedTabDefinition get blueprint => RoutedTabDefinition(
      slug: NavigationPaths.blueprint,
      route: const BlueprintSectionRoute(),
      label: CommonStrings.blueprint,
      icon: Icons.grid_on);
  static RoutedTabDefinition get tickets => RoutedTabDefinition(
      slug: NavigationPaths.tickets,
      route: const TicketsSectionRoute(),
      label: OrdersStrings.itemsPlural,
      icon: Icons.local_activity);
  static RoutedTabDefinition get orders => RoutedTabDefinition(
      slug: NavigationPaths.orders,
      route: const OrdersNavigationRoute(),
      label: DataGridStrings.tabOrders,
      icon: Icons.shopping_cart);
  static RoutedTabDefinition get products => RoutedTabDefinition(
      slug: NavigationPaths.products,
      route: const ProductsSectionRoute(),
      label: CommonStrings.products,
      icon: Icons.category);
  static RoutedTabDefinition get report => RoutedTabDefinition(
      slug: NavigationPaths.report,
      route: const ReportSectionRoute(),
      label: DataGridStrings.tabReport,
      icon: Icons.stacked_bar_chart);
  static RoutedTabDefinition get emailTemplates => RoutedTabDefinition(
      slug: NavigationPaths.emailTemplates,
      route: const EmailTemplatesSectionRoute(),
      label: EmailTemplatesStrings.title,
      icon: Icons.email);
  static RoutedTabDefinition get emailDelivery => RoutedTabDefinition(
      slug: NavigationPaths.emailDelivery,
      route: const EmailDeliverySectionRoute(),
      label: EmailDeliveryStrings.title,
      icon: Icons.mail_outline);
  static RoutedTabDefinition get settings => RoutedTabDefinition(
      slug: NavigationPaths.settings,
      route: const SettingsSectionRoute(),
      label: CommonStrings.settings,
      icon: Icons.settings);
  static RoutedTabDefinition get changes => RoutedTabDefinition(
      slug: NavigationPaths.changes,
      route: const ChangesSectionRoute(),
      label: ClientChangesStrings.title,
      icon: Icons.history);

  static List<RoutedTabDefinition> get administration => [
        info,
        if (!AppConfig.isAllUnit) events,
        places,
        speakers,
        if (FeatureService.isFeatureEnabled(FeatureConstants.userGroups))
          groups,
        if (FeatureService.isFeatureEnabled(FeatureConstants.game)) game,
        if (FeatureService.isFeatureEnabled(FeatureConstants.services)) service,
        if (FeatureService.isFeatureEnabled(FeatureConstants.volunteers))
          volunteers,
        emailTemplates,
        if (RightsService.isEditorOrderView() || RightsService.isAdmin())
          emailDelivery,
        users,
        if (RightsService.isManager() || RightsService.isAdmin()) changes,
        if (RightsService.isUnitEditor()) settings
      ];
  static List<RoutedTabDefinition> get reservations => [
        orders,
        tickets,
        if (FeatureService.isFeatureEnabled(FeatureConstants.blueprint))
          blueprint,
        form,
        products,
        if (FeatureService.isFeatureEnabled(FeatureConstants.services))
          inventoryPools,
        report,
        emailTemplates,
        if (RightsService.isEditorOrderView() || RightsService.isAdmin())
          emailDelivery,
        users,
        if (RightsService.isUnitEditor()) settings
      ];
}
