import 'package:fstapp/components/navigation/navigation_paths.dart';
import 'package:auto_route/auto_route.dart';
import 'package:flutter/material.dart';
import 'package:fstapp/app_router.gr.dart';
import 'package:fstapp/components/navigation/routed_tab_scaffold.dart';
import 'package:fstapp/components/eshop/views/orders_history_content.dart';
import 'package:fstapp/components/eshop/views/orders_content.dart';
import '../orders_strings.dart';

@RoutePage(name: 'OrdersTabsRoute')
class OrdersTab extends StatelessWidget {
  const OrdersTab({super.key});
  @override
  Widget build(BuildContext context) {
    Localizations.localeOf(context);
    return RoutedTabScaffold(tabs: [
      RoutedTabDefinition(
          slug: NavigationPaths.current,
          route: const OrdersCurrentRoute(),
          label: OrdersStrings.ordersTab,
          icon: Icons.shopping_cart),
      RoutedTabDefinition(
          slug: NavigationPaths.history,
          route: const OrdersHistoryRoute(),
          label: OrdersStrings.ordersHistoryTab,
          icon: Icons.history),
    ]);
  }
}

@RoutePage()
class OrdersCurrentPage extends StatelessWidget {
  const OrdersCurrentPage({super.key});
  @override
  Widget build(BuildContext context) => OrdersContent();
}

@RoutePage()
class OrdersHistoryPage extends StatelessWidget {
  const OrdersHistoryPage({super.key});
  @override
  Widget build(BuildContext context) => OrdersHistoryContent();
}
