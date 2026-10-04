import 'package:auto_route/auto_route.dart';
import 'package:flutter/material.dart';
import 'package:fstapp/components/eshop/orders_strings.dart';
import 'package:fstapp/app_router.dart';
import 'package:fstapp/components/features/feature_constants.dart';
import 'package:fstapp/components/features/feature_service.dart';
import 'package:fstapp/components/single_data_grid/data_grid_action.dart';
import 'package:fstapp/components/single_data_grid/single_data_grid_controller.dart';
import 'package:fstapp/components/single_data_grid/single_table_data_grid.dart';
import 'package:fstapp/components/eshop/models/product_model.dart';
import 'package:fstapp/data_services/rights_service.dart';
import 'package:fstapp/components/eshop/db_eshop.dart';

import '../eshop_columns.dart';
import '../models/tb_eshop.dart';

class ProductsTab extends StatefulWidget {
  const ProductsTab({super.key});

  @override
  _ProductsTabState createState() => _ProductsTabState();
}

class _ProductsTabState extends State<ProductsTab> {
  SingleDataGridController<ProductModel>? _controller;
  String? _occasionLink;
  bool _isLoading = true;

  List<String> get columnIdentifiers => [
        EshopColumns.PRODUCT_ID,
        EshopColumns.PRODUCT_TYPE,
        EshopColumns.PRODUCT_TITLE,
        if (FeatureService.isFeatureEnabled(FeatureConstants.ticket))
          EshopColumns.PRODUCT_SHORT_TITLE,
        if (FeatureService.isFeatureEnabled(FeatureConstants.services))
          EshopColumns.PRODUCT_INCLUDED_INVENTORY,
        EshopColumns.PRODUCT_DESCRIPTION,
        EshopColumns.PRODUCT_IS_HIDDEN,
        EshopColumns.PRODUCT_PRICE,
        EshopColumns.PRODUCT_CURRENCY_CODE,
        if (FeatureService.isFeatureEnabled(FeatureConstants.deposit) &&
            !FeatureService.isDepositVirtualMode())
          EshopColumns.PRODUCT_DEPOSIT,
        if (FeatureService.isDepositVirtualMode())
          EshopColumns.PRODUCT_SURCHARGE,
        if (FeatureService.isDepositVirtualMode())
          EshopColumns.PRODUCT_SURCHARGE_CURRENCY,
        EshopColumns.PRODUCT_PAID_COUNT,
        EshopColumns.PRODUCT_ORDERED_COUNT,
        EshopColumns.PRODUCT_MAXIMUM,
        EshopColumns.PRODUCT_USED_IN_FORMS,
        EshopColumns.PRODUCT_ORDER,
      ];

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final newOccasionLink = context.routeData.inheritedPathParams
        .getString(AppRouter.linkFormatted);
    // Initialize only once when the link is available
    if (_occasionLink == null) {
      _occasionLink = newOccasionLink;
      _initializeController();
    }
  }

  Future<void> _initializeController() async {
    if (_occasionLink == null) {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
      return;
    }

    final initialBundle =
        await DbEshop.getProductsAndTypesForOccasion(_occasionLink!);
    if (!mounted) return;

    final newController = SingleDataGridController<ProductModel>(
      context: context,
      loadData: () async {
        final newBundle =
            await DbEshop.getProductsAndTypesForOccasion(_occasionLink!);
        return newBundle.products;
      },
      fromPlutoJson: ProductModel.fromPlutoJson,
      firstColumnType: DataGridFirstColumn.delete,
      idColumn: TbEshop.products.id,
      actionsExtended: DataGridActionsController(
        areAllActionsEnabled: () => RightsService.canUpdateOrders(),
        isAddActionPossible: () => false,
      ),
      columns: EshopColumns.generateColumns(
        context,
        columnIdentifiers,
        data: {
          EshopColumns.PRODUCT_DESCRIPTION: RightsService.currentOccasionId(),
          // Use the dependencies from the initial fetch
          EshopColumns.PRODUCT_INCLUDED_INVENTORY:
              initialBundle.inventoryContexts,
          EshopColumns.PRODUCT_USED_IN_FORMS: initialBundle.forms,
        },
      ),
    );

    // Update the state to assign the controller and stop loading
    if (mounted) {
      setState(() {
        _controller = newController;
        _isLoading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return const Center(child: CircularProgressIndicator());
    }

    // If loading is finished but the controller is still null,
    // it means initialization failed or there was no data.
    if (_controller == null) {
      return Center(child: Text(OrdersStrings.noDataToDisplay));
    }

    // Pass the state-managed controller to the grid
    return SingleTableDataGrid<ProductModel>(_controller!);
  }
}
