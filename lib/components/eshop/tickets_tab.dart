import 'ticket_cancellation_updates.dart';
import 'package:fstapp/components/eshop/order_item_strings.dart';
import 'package:fstapp/components/eshop/eshop_column_ids.dart';
import 'package:fstapp/components/single_data_grid/data_grid_action_confirmation.dart';
import 'package:fstapp/components/eshop/order_grid_filters.dart';
import 'package:auto_route/auto_route.dart';
import 'package:flutter/material.dart';
import 'package:fstapp/app_router.dart';
import 'package:fstapp/components/_shared/common_strings.dart';
import 'package:fstapp/components/features/feature_constants.dart';
import 'package:fstapp/components/features/feature_service.dart';
import 'package:fstapp/components/single_data_grid/data_grid_action.dart';
import 'package:fstapp/components/single_data_grid/single_data_grid_controller.dart';
import 'package:fstapp/components/single_data_grid/single_table_data_grid.dart';
import 'package:fstapp/components/eshop/models/ticket_model.dart';
import 'package:fstapp/data_services/rights_service.dart';
import 'package:fstapp/components/eshop/db_tickets.dart';
import 'package:fstapp/components/eshop/ticket_commands.dart';
import 'package:fstapp/services/dialog_helper.dart';
import 'package:fstapp/components/eshop/ticket_code_helper.dart';
import 'package:fstapp/services/platform_helper.dart'; // Import PlatformHelper

import 'eshop_columns.dart';
import 'orders_strings.dart';

class TicketsTab extends StatefulWidget {
  const TicketsTab({super.key});

  @override
  State<TicketsTab> createState() => _TicketsTabState();
}

class _TicketsTabState extends State<TicketsTab> {
  SingleDataGridController<TicketModel>? _controller;
  String? occasionLink;
  bool _isLoading = true;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final newOccasionLink = context.routeData.inheritedPathParams.getString(
      AppRouter.linkFormatted,
    );
    // Initialize only once when the link is available
    if (occasionLink == null) {
      occasionLink = newOccasionLink;
      _initializeController();
    }
  }

  Future<void> _initializeController() async {
    if (occasionLink == null) {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
      return;
    }

    final List<String> columnIdentifiers = [
      EshopColumnIds.TICKET_ID,
      EshopColumnIds.ORDER_SEQUENCE,
      EshopColumnIds.ORDER_SYMBOL,
      EshopColumnIds.ORDER_DATA,
      EshopColumnIds.TICKET_SYMBOL,
      EshopColumnIds.TICKET_ORIGIN,
      EshopColumnIds.TICKET_BATCH,
      EshopColumnIds.TICKET_SALE_STATE,
      EshopColumnIds.TICKET_CREATED_AT,
      EshopColumnIds.TICKET_STATE,
      if (PlatformHelper.isWeb &&
          FeatureService.isFeatureEnabled(FeatureConstants.ticket))
        EshopColumnIds.TICKET_DOWNLOAD,
      if (FeatureService.isFeatureEnabled(FeatureConstants.ticket))
        EshopColumnIds.TICKET_CONFIRM,
      EshopColumnIds.TICKET_TOTAL_PRICE,
      if (FeatureService.isFeatureEnabled(FeatureConstants.blueprint))
        EshopColumnIds.TICKET_SPOT,
      EshopColumnIds.TICKET_PRODUCTS_EXTENDED,
      EshopColumnIds.TICKET_PRODUCTS_EDIT,
      if (FeatureService.isFeatureEnabled(FeatureConstants.ticket))
        EshopColumnIds.TICKET_LAST_CHANGE,
      EshopColumnIds.TICKET_NOTE,
      EshopColumnIds.TICKET_NOTE_HIDDEN,
    ];

    final newController = SingleDataGridController<TicketModel>(
      context: context,
      additionalFilterEnabled: true,
      additionalRowPredicate: OrderGridFilters.ticketIsNonCancelled,
      headerFilterBuilder: (context, controller) =>
          OrderGridFilters.filterButton(context, controller,
              label: OrderItemStrings.validTickets),
      loadData: () => DbTickets.getAllTickets(occasionLink!),
      fromPlutoJson: TicketModel.fromPlutoJson,
      firstColumnType: DataGridFirstColumn.check,
      idColumn: EshopColumnIds.TICKET_ID,
      actionsExtended: DataGridActionsController(
        areAllActionsEnabled: RightsService.canUpdateOrders,
        isAddActionPossible: () => false,
      ),
      headerChildren: [
        DataGridAction(
          name: CommonStrings.cancel,
          requiresSelection: true,
          action: (SingleDataGridController singleDataGrid, [_]) =>
              _stornoTickets(singleDataGrid),
          isEnabled: () =>
              RightsService.canUpdateOrders() &&
              (_controller?.visibleCheckedRows
                      .every(OrderGridFilters.ticketIsNonCancelled) ??
                  false),
        ),
        if (FeatureService.isFeatureEnabled(FeatureConstants.ticket))
          DataGridAction(
            name: OrderItemStrings.scanActionText,
            requiresSelection: false,
            action: (SingleDataGridController singleDataGrid, [_]) =>
                _scanTickets(singleDataGrid),
            isEnabled: RightsService.canUpdateOrders,
          ),
      ],
      columns: EshopColumns.generateColumns(
        context,
        columnIdentifiers,
        data: {
          EshopColumnIds.TICKET_PRODUCTS_EXTENDED:
              EshopColumns.productCategories,
          EshopColumnIds.TICKET_PRODUCTS_EDIT: refreshData,
          EshopColumnIds.TICKET_CONFIRM: refreshData,
          EshopColumnIds.TICKET_DOWNLOAD: null,
        },
      ),
      exportOptions: ExportOptions(fileName: "$occasionLink-tickets"),
    );

    if (mounted) {
      setState(() {
        _controller = newController;
        _isLoading = false;
      });
    }
  }

  Future<void> refreshData() async {
    await _controller?.reloadData();
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return const Center(child: CircularProgressIndicator());
    }

    // If loading is finished but the controller is still null,
    // it means initialization failed or there was no data context.
    if (_controller == null) {
      return Center(child: Text(OrdersStrings.noDataToDisplay));
    }

    return SingleTableDataGrid<TicketModel>(_controller!);
  }

  Future<void> _scanTickets(SingleDataGridController singleDataGrid) async {
    await TicketCodeHelper.showScanTicketCode(
      context,
      OrderItemStrings.scanActionText,
      occasionLink!,
    );
    refreshData();
  }

  Future<void> _stornoTickets(SingleDataGridController singleDataGrid) async {
    var selectedTickets = _getCheckedTickets(singleDataGrid);

    if (selectedTickets.isEmpty) {
      return;
    }

    var confirm = await DataGridActionConfirmation.show<TicketModel>(
      context: context,
      title: CommonStrings.cancel,
      message: OrderItemStrings.cancelItemsConfirmationText,
      items: selectedTickets,
      itemsLabel: OrderItemStrings.itemsPlural,
      confirmButtonText: CommonStrings.cancel,
      groupBy: (ticket) => ticket.relatedOrder,
    );

    if (confirm && mounted) {
      final checkedIds =
          _getCheckedTickets(singleDataGrid).map((ticket) => ticket.id).toSet();
      final confirmedIds = selectedTickets
          .where((ticket) => checkedIds.contains(ticket.id))
          .map((ticket) => ticket.id!)
          .toList();
      if (confirmedIds.isEmpty) return;
      TicketCancellationOutcome? outcome;
      final success = await DialogHelper.showProgressDialogAsync(
        context,
        OrdersStrings.processing,
        1,
        futures: [
          () async {
            outcome = await DbTickets.stornoTickets(
              confirmedIds,
            );
          },
        ],
      );
      refreshData();
      if (!success || !mounted || outcome == null) return;

      await showTicketCancellationUpdates(context, outcome!);
    }
  }

  List<TicketModel> _getCheckedTickets(
    SingleDataGridController singleDataGrid,
  ) {
    return List<TicketModel>.from(
      singleDataGrid.visibleCheckedRows
          .where(OrderGridFilters.ticketIsNonCancelled)
          .map((row) => TicketModel.fromPlutoJson(row.toJson())),
    );
  }
}
