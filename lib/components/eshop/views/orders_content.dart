import 'package:flutter/material.dart';
import 'package:fstapp/app_router.dart';
import 'package:fstapp/components/_shared/common_strings.dart';
import 'package:fstapp/components/features/form_feature.dart';
import 'package:fstapp/components/single_data_grid/data_grid_action.dart';
import 'package:fstapp/components/single_data_grid/single_data_grid_controller.dart';
import 'package:fstapp/components/single_data_grid/single_table_data_grid.dart';
import 'package:fstapp/components/eshop/models/order_model.dart';
import 'package:fstapp/components/eshop/models/tb_eshop.dart';
import 'package:fstapp/components/features/feature_constants.dart';
import 'package:fstapp/components/features/feature_service.dart';
import 'package:fstapp/components/eshop/db_eshop.dart';
import 'package:fstapp/data_services/rights_service.dart';
import 'package:fstapp/components/eshop/db_orders.dart';
import 'package:fstapp/components/eshop/db_tickets.dart';
import 'package:fstapp/components/occasion/db_occasions.dart';
import 'package:fstapp/components/occasion/occasion_model.dart';
import 'package:auto_route/auto_route.dart';
import 'package:fstapp/components/forms/widgets_view/form_helper.dart';
import 'package:fstapp/services/dialog_helper.dart';

import '../eshop_columns.dart';
import '../orders_strings.dart';

// The class has been renamed from OrdersTab to OrdersContent
class OrdersContent extends StatefulWidget {
  const OrdersContent({super.key});

  @override
  _OrdersContentState createState() => _OrdersContentState();
}

bool canSaveOrderGridChanges({
  required bool isOrderEditor,
  required bool isUnitManager,
}) =>
    isOrderEditor || isUnitManager;

// The state class has been renamed accordingly
class _OrdersContentState extends State<OrdersContent> {
  String? occasionLink;
  SingleDataGridController<OrderModel>? controller;
  int? unitId;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final newOccasionLink =
        context.routeData.params.getString(AppRouter.linkFormatted);
    // Initialize only once when the link is available
    if (occasionLink == null) {
      occasionLink = newOccasionLink;
      _initializeController();
    }
  }

  Future<void> _initializeController() async {
    if (occasionLink == null) return;

    // Fetch all data in one request
    var futures = await Future.wait([
      DbOrders.getOrdersTabData(occasionLink: occasionLink!),
      DbOccasions.getOccasionByLink(occasionLink!),
    ]);

    final bundle = futures[0] as ReservationsBundle;
    final occasion = futures[1] as OccasionModel;
    unitId = occasion.unit;

    if (!mounted) return;

    final forms = bundle.forms;

    // Check if any field across all forms is a non-ticket 'note' field.
    final hasOrderNoteField = forms.any((form) => (form.relatedFields).any(
        (field) =>
            field.type == FormHelper.fieldTypeNote &&
            (field.isTicketField ?? false) == false));

    var formFeat =
        FeatureService.getFeatureDetails(FeatureConstants.form) as FormFeature;

    // Start with the base list of columns
    List<String> columnIdentifiers = [
      EshopColumns.ORDER_ID,
      EshopColumns.ORDER_SYMBOL,
      EshopColumns.ORDER_DATA,
      EshopColumns.ORDER_EMAIL,
      if (!FeatureService.isFeatureEnabled(FeatureConstants.ticket))
        EshopColumns.TICKET_PRODUCTS,
      EshopColumns.ORDER_CREATED_AT,
      EshopColumns.ORDER_STATE,
      if (FeatureService.isFeatureEnabled(FeatureConstants.contract))
        EshopColumns.ORDER_CONTRACT_DOWNLOAD,
      EshopColumns.ORDER_PRICE,
      EshopColumns.PAYMENT_INFO_PAID,
      EshopColumns.PAYMENT_INFO_RETURNED,
      EshopColumns.PAYMENT_INFO_VARIABLE_SYMBOL,
      if (hasOrderNoteField) EshopColumns.ORDER_DATA_NOTE,
      EshopColumns.ORDER_NOTE_HIDDEN,
      if (formFeat.isEnabled && (formFeat.reminderIsEnabled ?? false))
        EshopColumns.PAYMENT_INFO_REMINDER_SENT,
      EshopColumns.PAYMENT_INFO_DEADLINE,
      if (FeatureService.isFeatureEnabled(FeatureConstants.deposit))
        EshopColumns.PAYMENT_INFO_DEPOSIT_DEADLINE,
      EshopColumns.ORDER_TRANSACTIONS,
      EshopColumns.ORDER_HISTORY,
    ];

    // Conditionally add the form column if there are multiple forms
    if (forms.length > 1) {
      final symbolIndex = columnIdentifiers.indexOf(EshopColumns.ORDER_SYMBOL);
      columnIdentifiers.insert(symbolIndex + 1, EshopColumns.ORDER_FORM);
    }

    // Create the controller with the final column list
    List<OrderModel>? firstLoadOrders = bundle.orders;

    final newController = SingleDataGridController<OrderModel>(
      context: context,
      loadData: () async {
        if (firstLoadOrders != null) {
          final orders = firstLoadOrders;
          firstLoadOrders =
              null; // Clear it so subsequent reloads fetch fresh data
          return orders!;
        }
        final newBundle =
            await DbOrders.getOrdersTabData(occasionLink: occasionLink!);
        return newBundle.orders;
      },
      fromPlutoJson: OrderModel.fromPlutoJson,
      firstColumnType: RightsService.isUnitManager()
          ? DataGridFirstColumn.deleteAndCheck
          : DataGridFirstColumn.check,
      idColumn: TbEshop.orders.id,
      actionsExtended: DataGridActionsController(
        areAllActionsEnabled: () => canSaveOrderGridChanges(
          isOrderEditor: RightsService.isEditorOrder(),
          isUnitManager: RightsService.isUnitManager(),
        ),
        isAddActionPossible: () => false,
      ),
      headerChildren: [
        DataGridAction(
          name: CommonStrings.cancel,
          action: (SingleDataGridController singleDataGrid, [_]) =>
              cancelOrders(singleDataGrid),
          isEnabled: RightsService.isOrderEditor,
        ),
        DataGridAction(
          name: OrdersStrings.synchronizePayments,
          action: (SingleDataGridController singleDataGrid, [_]) =>
              synchronizePayments(),
          isEnabled: RightsService.isOrderEditor,
        ),
        DataGridAction(
          name: OrdersStrings.sendActionText,
          action: (SingleDataGridController singleDataGrid, [_]) =>
              sendTicketsOrConfirmations(singleDataGrid),
          isEnabled: RightsService.isOrderEditor,
        ),
      ],
      columns: EshopColumns.generateColumns(context, columnIdentifiers, data: {
        EshopColumns.ORDER_TRANSACTIONS: refreshData,
        EshopColumns.PAYMENT_INFO_PAID: refreshData,
        "unitId": unitId,
      }),
    );

    if (mounted) {
      setState(() {
        controller = newController;
      });
    }
  }

  Future<void> refreshData() async {
    await controller?.reloadData();
  }

  @override
  Widget build(BuildContext context) {
    if (controller == null) {
      return const Center(child: CircularProgressIndicator());
    }
    return SingleTableDataGrid<OrderModel>(controller!);
  }

  Future<void> synchronizePayments() async {
    if (occasionLink == null) return;
    await DbEshop.fetchTransactions(occasionLink!);
    refreshData();
  }

  Future<void> cancelOrders(SingleDataGridController singleDataGrid) async {
    var selected = _getChecked(singleDataGrid);
    if (selected.isEmpty) {
      return;
    }

    if (selected.isNotEmpty) {
      var confirm = await DialogHelper.showConfirmationDialog(
          context,
          CommonStrings.cancel,
          "${OrdersStrings.cancelOrdersConfirmationText} (${selected.length})");

      if (confirm && mounted) {
        var futures = selected.map((s) {
          return () async {
            await DbOrders.stornoOrder(s.id!);
          };
        }).toList();

        await DialogHelper.showProgressDialogAsync(
            context, OrdersStrings.processing, futures.length,
            futures: futures);
        refreshData();
      }
    }
  }

  Future<void> sendTicketsOrConfirmations(
      SingleDataGridController singleDataGrid) async {
    if (occasionLink == null) return;
    var selected = _getChecked(singleDataGrid);
    if (selected.isEmpty) {
      return;
    }

    List<OrderModel> selectedFull = [];

    var ordersBundle =
        await DbOrders.getAllOrdersBundle(occasionLink: occasionLink!);
    for (var s in selected) {
      var o = ordersBundle.orders.firstWhere((o) => o.id == s.id);
      selectedFull.add(o);
    }
    var stateChange =
        selectedFull.where((s) => s.state == OrderModel.orderedState);
    if (stateChange.isNotEmpty) {
      var confirm = await DialogHelper.showConfirmationDialog(
          context,
          OrdersStrings.changeStateToPaid,
          "${OrdersStrings.changeStateToPaidConfirmation} (${stateChange.length})");

      if (confirm) {
        var futures = stateChange.map((s) {
          return () async {
            await DbOrders.updateOrderAndTicketsToPaid(s.id!);
          };
        }).toList();

        await DialogHelper.showProgressDialogAsync(
            context, OrdersStrings.processing, futures.length,
            futures: futures, isBasic: true);
        refreshData();
      }
    }

    var confirm = await DialogHelper.showConfirmationDialog(
        context,
        OrdersStrings.sendActionText,
        "${OrdersStrings.sendActionConfirmationText} (${selected.length})");

    if (confirm) {
      var futures = selectedFull.map((s) {
        return () async {
          await sendTicketsToEmail(s);
        };
      }).toList();

      await DialogHelper.showProgressDialogAsync(
          context, OrdersStrings.processing, futures.length,
          futures: futures);
      refreshData();
    }
  }

  Future<void> sendTicketsToEmail(OrderModel order) async {
    await DbTickets.sendTicketsToEmail(
      orderId: order.id!,
      email: order.data!["email"],
    );
  }

  List<OrderModel> _getChecked(SingleDataGridController singleDataGrid) {
    return List<OrderModel>.from(
      singleDataGrid.stateManager.refRows.originalList
          .where((row) => row.checked == true)
          .map((row) => OrderModel.fromPlutoJson(row.toJson())),
    );
  }
}
