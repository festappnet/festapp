import 'package:flutter/material.dart';
import 'package:fstapp/components/eshop/views/orders_history_content.dart';
import 'package:fstapp/components/single_data_grid/data_grid_helper.dart';
import 'package:fstapp/components/eshop/views/orders_content.dart'; // The original OrdersTab is now here
import 'package:fstapp/theme_config.dart';

import '../orders_strings.dart';

class OrdersTab extends StatefulWidget {
  const OrdersTab({super.key});

  @override
  _OrdersTabState createState() => _OrdersTabState();
}

class _OrdersTabState extends State<OrdersTab>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;
  // Set the number of tabs. For this example, we have "Orders" and a placeholder "Products".
  final int _tabLength = 2;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: _tabLength, vsync: this);
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: _tabLength,
      child: Column(
        children: [
          Container(
            color: ThemeConfig.backgroundColor(context),
            alignment: Alignment.centerLeft,
            child: TabBar(
              controller: _tabController,
              isScrollable: true,
              tabAlignment: TabAlignment.start,
              tabs: [
                DataGridHelper.buildTab(
                    context, Icons.shopping_cart, OrdersStrings.ordersTab),
                DataGridHelper.buildTab(
                    context, Icons.history, OrdersStrings.ordersHistoryTab),
              ],
            ),
          ),
          Expanded(
            child: TabBarView(
              controller: _tabController,
              physics: const NeverScrollableScrollPhysics(),
              children: const [
                OrdersContent(), // Your original widget is now the content of the first tab
                OrdersHistoryContent(), // A placeholder for the second tab's content
              ],
            ),
          ),
        ],
      ),
    );
  }
}
