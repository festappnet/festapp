import 'product_price_waves_dialog.dart';
import '../models/product_price_wave.dart';
import 'package:fstapp/components/single_data_grid/admin_tab_activity.dart';

import 'dart:async';

import 'package:trina_grid/trina_grid.dart';
import 'package:fstapp/services/exception_handler.dart';

import 'product_price_change_cell.dart';
import 'product_price_changes_dialog.dart';

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
  State<ProductsTab> createState() => _ProductsTabState();
}

class _ProductsTabState extends State<ProductsTab>
    with WidgetsBindingObserver, AutomaticKeepAliveClientMixin {
  bool _active = true;
  @override
  bool get wantKeepAlive => true;
  Timer? _refreshTimer;
  bool _refreshing = false;
  bool _refreshAvailable = false;
  DateTime? _nextChange;
  Duration _serverClockOffset = Duration.zero;
  bool _dialogOpen = false;
  final _planFocusNodes = <int, FocusNode>{};
  double _automaticPlanWidth = 180;
  bool _manualPlanWidth = false;

  bool get _dirty => _controller?.hasUnsavedChanges ?? false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _refreshTimer = Timer.periodic(
      const Duration(seconds: 60),
      (_) => _refresh(),
    );
  }

  @override
  void dispose() {
    _controller?.reloadGeneration.removeListener(_explicitReloaded);
    for (final node in _planFocusNodes.values) {
      node.dispose();
    }
    _refreshTimer?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) _refresh(force: true);
  }

  void _trackPlans(List<ProductModel> products) {
    if (products.isNotEmpty) {
      _serverClockOffset = products.first.priceClockOffset;
    }
    final times = products
        .expand((product) => [
              ...product.priceChanges
                  .where((p) => !p.applied && p.failureCode == null)
                  .map((p) => p.time),
              ...product.visibilityChanges
                  .where((p) => !p.applied && p.failureCode == null)
                  .map((p) => p.time),
            ])
        .toList()
      ..sort();
    _nextChange = times.firstOrNull;
    if (_controller != null) {
      final column = _controller!.columns.firstWhere(
        (c) => c.field == EshopColumns.PRODUCT_PRICE_CHANGES,
      );
      if (column.width != _automaticPlanWidth) _manualPlanWidth = true;
      if (!_manualPlanWidth) {
        _automaticPlanWidth =
            products.any((p) => p.priceChanges.isNotEmpty) ? 300 : 180;
        column.width = _automaticPlanWidth;
      }
    }
  }

  Future<void> _refresh({bool force = false}) async {
    if (!_active ||
        _controller == null ||
        _isLoading ||
        _refreshing ||
        _dialogOpen ||
        !mounted) {
      return;
    }
    if (!force &&
        !_refreshAvailable &&
        (_nextChange == null ||
            _nextChange!.isAfter(
              DateTime.now().toUtc().add(_serverClockOffset),
            ))) {
      return;
    }
    if (_dirty) {
      if (!_refreshAvailable) setState(() => _refreshAvailable = true);
      return;
    }
    _refreshing = true;
    final success = await ExceptionHandler.guard(
      context,
      futureFunction: () => _controller!.reloadIfClean(
        canApply: () => mounted && _active && !_dialogOpen,
      ),
    );
    if (mounted) setState(() => _refreshAvailable = success != true);
    _refreshing = false;
  }

  void _explicitReloaded() {
    if (mounted && _refreshAvailable) setState(() => _refreshAvailable = false);
  }

  Future<void> _openPlans(int id) async {
    if (_dirty) {
      setState(() => _refreshAvailable = true);
      return;
    }
    final bundle = await ExceptionHandler.guard(
      context,
      futureFunction: () =>
          DbEshop.getProductsAndTypesForOccasion(_occasionLink!),
    );
    if (!mounted || bundle == null) return;
    final product = bundle.products.where((p) => p.id == id).firstOrNull;
    if (product == null) return;
    var openWaves = false;
    _dialogOpen = true;
    await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (context) => ProductPriceChangesDialog(
        product: product,
        suggestedTimes:
            ProductPriceWave.columns(bundle.priceWaves, bundle.products)
                .map((w) => w.time)
                .where((time) => time.isAfter(product.priceNow))
                .toList(),
        canEdit: RightsService.canUpdateOrders(),
        onOpenWaves: () => openWaves = true,
        reload: () async {
          final refreshed = await DbEshop.getProductsAndTypesForOccasion(
            _occasionLink!,
          );
          return refreshed.products.firstWhere((p) => p.id == id);
        },
      ),
    );
    _dialogOpen = false;
    if (!mounted) return;
    if (openWaves) {
      await _openWaves();
    } else {
      await _refresh(force: true);
    }
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _planFocusNodes[id]?.requestFocus();
    });
  }

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
    final active = AdminTabActivity.isActive(context);
    if (active && !_active) {
      WidgetsBinding.instance.addPostFrameCallback(
        (_) => _refresh(force: true),
      );
    }
    _active = active;
    final newOccasionLink = context.routeData.inheritedPathParams.getString(
      AppRouter.linkFormatted,
    );
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

    final initialBundle = await DbEshop.getProductsAndTypesForOccasion(
      _occasionLink!,
    );
    if (!mounted) return;
    _trackPlans(initialBundle.products);

    _automaticPlanWidth =
        initialBundle.products.any((p) => p.priceChanges.isNotEmpty)
            ? 300
            : 180;
    List<ProductModel>? firstLoadProducts = initialBundle.products;
    final newController = SingleDataGridController<ProductModel>(
      context: context,
      refreshOnTabActivation: false,
      loadData: () async {
        if (firstLoadProducts != null) {
          final products = firstLoadProducts!;
          firstLoadProducts = null;
          return products;
        }
        final newBundle = await DbEshop.getProductsAndTypesForOccasion(
          _occasionLink!,
        );
        _trackPlans(newBundle.products);
        return newBundle.products;
      },
      fromPlutoJson: ProductModel.fromPlutoJson,
      firstColumnType: DataGridFirstColumn.delete,
      idColumn: TbEshop.products.id,
      columnHelp: {
        EshopColumns.PRODUCT_SHORT_TITLE: OrdersStrings.gridShortTitleHelp,
        EshopColumns.PRODUCT_PRICE: OrdersStrings.futurePricesRemain,
        EshopColumns.PRODUCT_MAXIMUM: OrdersStrings.gridMaxHelp,
      },
      actionsExtended: DataGridActionsController(
        areAllActionsEnabled: () => RightsService.canUpdateOrders(),
        isAddActionPossible: () => false,
      ),
      headerChildren: [
        DataGridAction(
          name: OrdersStrings.priceWaves,
          requiresSelection: false,
          action: (SingleDataGridController controller, [_]) => _openWaves(),
          isEnabled: () => !_dialogOpen,
        ),
      ],
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

    final priceColumn = newController.columns.firstWhere(
      (c) => c.field == EshopColumns.PRODUCT_PRICE,
    );
    priceColumn.title = OrdersStrings.scheduledCurrentPrice;
    priceColumn.width = 180;
    final currencyIndex = newController.columns.indexWhere(
      (c) => c.field == EshopColumns.PRODUCT_CURRENCY_CODE,
    );
    newController.columns.insert(
      currencyIndex + 1,
      TrinaColumn(
        title: OrdersStrings.priceChanges,
        field: EshopColumns.PRODUCT_PRICE_CHANGES,
        type: TrinaColumnType.text(),
        readOnly: true,
        enableSorting: false,
        enableFilterMenuItem: false,
        width: initialBundle.products.any((p) => p.priceChanges.isNotEmpty)
            ? 300
            : 180,
        renderer: (cell) {
          final model = cell.row.cells[EshopColumns.PRODUCT_MODEL_REFERENCE]!
              .value as ProductModel;
          return ProductPriceChangeCell(
            focusNode: _planFocusNodes.putIfAbsent(
              model.id!,
              () => FocusNode(),
            ),
            canEdit: RightsService.canUpdateOrders(),
            product: model,
            onOpen: () => _openPlans(model.id!),
          );
        },
      ),
    );

    newController.reloadGeneration.addListener(_explicitReloaded);

    // Update the state to assign the controller and stop loading
    if (mounted) {
      setState(() {
        _controller = newController;
        _isLoading = false;
      });
    }
  }

  Future<void> _openWaves() async {
    if (_dirty) {
      setState(() => _refreshAvailable = true);
      return;
    }
    final bundle = await ExceptionHandler.guard(context,
        futureFunction: () =>
            DbEshop.getProductsAndTypesForOccasion(_occasionLink!));
    if (!mounted || bundle == null) return;
    _dialogOpen = true;
    await showDialog<void>(
        context: context,
        barrierDismissible: false,
        builder: (_) => ProductPriceWavesDialog(
            occasionLink: _occasionLink!,
            initialBundle: bundle,
            canEdit: RightsService.canUpdateOrders()));
    _dialogOpen = false;
    if (mounted) await _refresh(force: true);
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    if (_isLoading) {
      return const Center(child: CircularProgressIndicator());
    }

    // If loading is finished but the controller is still null,
    // it means initialization failed or there was no data.
    if (_controller == null) {
      return Center(child: Text(OrdersStrings.noDataToDisplay));
    }

    // Pass the state-managed controller to the grid
    return Column(
      children: [
        if (_refreshAvailable)
          Padding(
            padding: const EdgeInsets.all(8),
            child: Text(OrdersStrings.priceRefresh),
          ),
        Expanded(child: SingleTableDataGrid<ProductModel>(_controller!)),
      ],
    );
  }
}
