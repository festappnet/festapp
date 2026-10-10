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
import 'package:fstapp/components/eshop/db_eshop.dart';
import 'package:fstapp/components/eshop/ticket_commands.dart';
import 'package:fstapp/services/dialog_helper.dart';
import 'package:fstapp/services/exception_handler.dart';
import 'package:fstapp/components/eshop/ticket_code_helper.dart';
import 'package:fstapp/services/toast_helper.dart';
import 'package:fstapp/services/platform_helper.dart'; // Import PlatformHelper

import 'db_orders.dart';
import 'views/order_update_email_dialog.dart';
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
      EshopColumns.TICKET_ID,
      EshopColumns.ORDER_SEQUENCE,
      EshopColumns.ORDER_SYMBOL,
      EshopColumns.ORDER_DATA,
      EshopColumns.TICKET_SYMBOL,
      EshopColumns.TICKET_CREATED_AT,
      EshopColumns.TICKET_STATE,
      if (PlatformHelper.isWeb &&
          FeatureService.isFeatureEnabled(FeatureConstants.ticket))
        EshopColumns.TICKET_DOWNLOAD,
      if (FeatureService.isFeatureEnabled(FeatureConstants.ticket))
        EshopColumns.TICKET_CONFIRM,
      EshopColumns.TICKET_TOTAL_PRICE,
      if (FeatureService.isFeatureEnabled(FeatureConstants.blueprint))
        EshopColumns.TICKET_SPOT,
      EshopColumns.TICKET_PRODUCTS_EXTENDED,
      EshopColumns.TICKET_PRODUCTS_EDIT,
      if (FeatureService.isFeatureEnabled(FeatureConstants.ticket))
        EshopColumns.TICKET_LAST_CHANGE,
      EshopColumns.TICKET_NOTE,
      EshopColumns.TICKET_NOTE_HIDDEN,
    ];

    final newController = SingleDataGridController<TicketModel>(
      context: context,
      additionalFilterEnabled: true,
      additionalRowPredicate: OrderGridFilters.ticketIsNonCancelled,
      headerFilterBuilder: (context, controller) =>
          OrderGridFilters.filterButton(context, controller,
              label: OrdersStrings.validTickets),
      loadData: () => DbTickets.getAllTickets(occasionLink!),
      fromPlutoJson: TicketModel.fromPlutoJson,
      firstColumnType: DataGridFirstColumn.check,
      idColumn: EshopColumns.TICKET_ID,
      actionsExtended: DataGridActionsController(
        areAllActionsEnabled: RightsService.isEditorOrder,
        isAddActionPossible: () => false,
      ),
      headerChildren: [
        DataGridAction(
          name: CommonStrings.cancel,
          requiresSelection: true,
          action: (SingleDataGridController singleDataGrid, [_]) =>
              _stornoTickets(singleDataGrid),
          isEnabled: () =>
              RightsService.isOrderEditor() &&
              (_controller?.visibleCheckedRows
                      .every(OrderGridFilters.ticketIsNonCancelled) ??
                  false),
        ),
        if (FeatureService.isFeatureEnabled(FeatureConstants.ticket))
          DataGridAction(
            name: OrdersStrings.scanActionText,
            requiresSelection: false,
            action: (SingleDataGridController singleDataGrid, [_]) =>
                _scanTickets(singleDataGrid),
            isEnabled: RightsService.isOrderEditor,
          ),
      ],
      columns: EshopColumns.generateColumns(
        context,
        columnIdentifiers,
        data: {
          EshopColumns.TICKET_PRODUCTS_EXTENDED: EshopColumns.productCategories,
          EshopColumns.TICKET_PRODUCTS_EDIT: refreshData,
          EshopColumns.TICKET_CONFIRM: refreshData,
          EshopColumns.TICKET_DOWNLOAD: null,
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
      OrdersStrings.scanActionText,
      occasionLink!,
    );
    refreshData();
  }

  Future<void> _stornoTickets(SingleDataGridController singleDataGrid) async {
    var selectedTickets = _getCheckedTickets(singleDataGrid);

    if (selectedTickets.isEmpty) {
      return;
    }

    var confirm = await DialogHelper.showConfirmationDialog(
      context,
      CommonStrings.cancel,
      "${OrdersStrings.cancelItemsConfirmationText} (${selectedTickets.length})",
    );

    if (confirm && mounted) {
      TicketCancellationOutcome? outcome;
      final success = await DialogHelper.showProgressDialogAsync(
        context,
        OrdersStrings.processing,
        1,
        futures: [
          () async {
            outcome = await DbTickets.stornoTickets(
              _getCheckedTickets(singleDataGrid)
                  .map((ticket) => ticket.id!)
                  .toList(),
            );
          },
        ],
      );
      refreshData();
      if (!success || !mounted || outcome == null) return;

      // Full cancellations enqueue their email in the database transaction.
      // Ask once per surviving order, even when several of its tickets were selected.
      for (final order in outcome!.updatedOrders) {
        if (!mounted) return;
        if (order.email.trim().isEmpty) continue;
        // Resolve a surviving ticket through existing order/detail RPCs so the
        // preview uses the same sent-history baseline as product editing.
        final bundle = await ExceptionHandler.guard<TicketDetailsBundle?>(
          context,
          defaultErrorMessage: OrdersStrings.sendEmailFailed,
          futureFunction: () async {
            final history = await DbOrders.getOrderHistory(order.id);
            final tickets = history.order.data?['tickets'] as List? ?? [];
            if (tickets.isEmpty) return null;
            return DbEshop.getProductsForTicket(
              (tickets.first as Map<String, dynamic>)['id'] as int,
            );
          },
        );
        if (bundle == null || !mounted) continue;
        final send = await showOrderUpdateEmailDialog(
          context,
          email: order.email,
          changes: bundle.changes,
          ticketId: bundle.ticket.id!,
          balance: (bundle.order.price ?? 0) - (bundle.paymentInfo?.paid ?? 0),
        );
        if (!send || !mounted) continue;
        final sent = await DialogHelper.showProgressDialogAsync(
          context,
          OrdersStrings.processing,
          1,
          futures: [
            () async {
              await DbEshop.sendTicketOrderUpdateEmail(order.id);
            },
          ],
        );
        if (mounted && sent) {
          ToastHelper.Show(context, OrdersStrings.sendEmailSuccess);
        }
      }
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
