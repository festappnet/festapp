import 'package:flutter/material.dart';
import 'package:fstapp/components/inventory/views/spot_management_view.dart';
import 'package:fstapp/theme_config.dart';
import 'package:fstapp/components/single_data_grid/data_grid_helper.dart';
import 'inventory_pool_settings_view.dart';
import 'inventory_strings.dart';
import 'resource_editor_view.dart';

class InventoryPoolDetailView extends StatefulWidget {
  final int poolId;
  final VoidCallback? onDeleteCompleted;
  final VoidCallback?
      onDataUpdated; // This will now be the _refreshDataForCurrentGroup function

  const InventoryPoolDetailView({
    super.key,
    required this.poolId,
    this.onDeleteCompleted,
    this.onDataUpdated,
  });

  @override
  _InventoryPoolDetailViewState createState() =>
      _InventoryPoolDetailViewState();
}

class _InventoryPoolDetailViewState extends State<InventoryPoolDetailView>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;
  final GlobalKey<SpotManagementViewState> _spotManagementKey = GlobalKey();

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  /// This function is passed as a callback to child tabs.
  /// When a child tab saves data, this function is called to trigger a reload
  /// in the parent (InventoryPoolsTab) and the matrix view.
  void _handleDataUpdate() {
    // Access the state via the key and call its public loadData method.
    _spotManagementKey.currentState?.fetchGridData();
    // Also notify the parent widget that data has been updated.
    widget.onDataUpdated?.call();
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Container(
          color: ThemeConfig.backgroundColor(context),
          alignment: Alignment.centerLeft,
          child: TabBar(
            controller: _tabController,
            isScrollable: true,
              tabAlignment: TabAlignment.start,
            tabs: [
              DataGridHelper.buildTab(context, Icons.grid_view,
                  InventoryStrings.detailTabOccupancy),
              DataGridHelper.buildTab(
                  context, Icons.house_siding, InventoryStrings.detailTabRooms),
              DataGridHelper.buildTab(
                  context, Icons.settings, InventoryStrings.detailTabSettings),
            ],
          ),
        ),
        Expanded(
          child: TabBarView(
            controller: _tabController,
            physics: const NeverScrollableScrollPhysics(),
            children: [
              SpotManagementView(
                key: _spotManagementKey,
                inventoryPoolId: widget.poolId,
              ),
              ResourceEditorView(
                inventoryPoolId: widget.poolId,
              ),
              InventoryPoolSettingsView(
                poolId: widget.poolId,
                // The settings view correctly calls the update handler.
                onPoolUpdated: _handleDataUpdate,
                // The delete action correctly calls the "go home" handler.
                onPoolDeleted: widget.onDeleteCompleted,
              ),
            ],
          ),
        ),
      ],
    );
  }
}
