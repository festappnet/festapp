import 'package:fstapp/widgets/app_dialog.dart';
import 'package:fstapp/components/single_data_grid/data_grid_action_confirmation.dart';
import '../../forms/waitlist_strings.dart';
import '../../forms/views/waitlist_offers_dialog.dart';
import 'package:fstapp/components/eshop/order_grid_filters.dart';
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
  required bool isUnitEditor,
}) =>
    isOrderEditor || isUnitManager || isUnitEditor;

// The state class has been renamed accordingly
class _OrdersContentState extends State<OrdersContent> {
  String? occasionLink;
  SingleDataGridController<OrderModel>? controller;
  int? unitId;
  bool loadFailed = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final newOccasionLink = context.routeData.inheritedPathParams
        .getString(AppRouter.linkFormatted);
    // Initialize only once when the link is available
    if (occasionLink == null) {
      occasionLink = newOccasionLink;
      _initializeController();
    }
  }

  Future<void> _initializeController() async {
    if (mounted) setState(() => loadFailed = false);
    try {
      await _loadController();
    } catch (error) {
      debugPrint('Could not load orders for occasion: $error');
      if (mounted) setState(() => loadFailed = true);
    }
  }

  Future<void> _loadController() async {
    if (occasionLink == null) return;

    // Fetch all data in one request
    var futures = await Future.wait([
      DbOrders.getOrdersTabData(occasionLink: occasionLink!),
      DbOccasions.getOccasionByLink(occasionLink!),
    ]);

    var bundle = futures[0] as ReservationsBundle;
    final occasion = futures[1] as OccasionModel;
    unitId = occasion.unit;

    if (!mounted) return;

    var forms = bundle.forms;

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
      EshopColumns.ORDER_SEQUENCE,
      EshopColumns.ORDER_SYMBOL,
      EshopColumns.ORDER_DATA,
      EshopColumns.ORDER_EMAIL,
      if (!FeatureService.isFeatureEnabled(FeatureConstants.ticket))
        EshopColumns.TICKET_PRODUCTS,
      EshopColumns.ORDER_CREATED_AT,
      EshopColumns.ORDER_STATE,
      EshopColumns.ORDER_WAITLIST,
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
      EshopColumns.ORDER_EMAIL_DELIVERY,
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

    final sendOffersAction = DataGridAction(
      name: WaitlistStrings.send,
      requiresSelection: false,
      action: (SingleDataGridController singleDataGrid, [_]) async {
        final eligible = forms.where((f) => f.waitlistEnabled).toList();
        final chosen = eligible.length == 1
            ? eligible.first
            : await showDialog<dynamic>(
                context: context,
                builder: (context) => AppSimpleDialog(
                      title: Text(WaitlistStrings.settings),
                      children: [
                        for (final f in eligible)
                          SimpleDialogOption(
                              onPressed: () => Navigator.pop(context, f),
                              child: Text(f.title ?? f.link ?? ''))
                      ],
                    ));
        if (chosen == null || !mounted) return;
        await showDialog(
            context: context,
            builder: (_) =>
                WaitlistOffersDialog(form: chosen, orders: bundle.orders));
        await refreshData();
      },
      isEnabled: RightsService.isEditorOrder,
    );

    final newController = SingleDataGridController<OrderModel>(
      context: context,
      additionalFilterEnabled: true,
      additionalRowPredicate: OrderGridFilters.orderIsActive,
      headerFilterBuilder: (context, controller) =>
          OrderGridFilters.filterButton(context, controller,
              label: WaitlistStrings.text('active')),
      loadData: () async {
        if (firstLoadOrders != null) {
          final orders = firstLoadOrders;
          firstLoadOrders =
              null; // Clear it so subsequent reloads fetch fresh data
          return orders!;
        }
        final newBundle =
            await DbOrders.getOrdersTabData(occasionLink: occasionLink!);
        bundle = newBundle;
        forms = newBundle.forms;
        final actions = controller?.headerChildren;
        actions?.removeWhere((action) => identical(action, sendOffersAction));
        if (RightsService.isEditorOrder() &&
            forms.any((f) => f.waitlistEnabled)) {
          actions?.insert(0, sendOffersAction);
        }
        return newBundle.orders;
      },
      fromPlutoJson: OrderModel.fromPlutoJson,
      firstColumnType:
          (RightsService.isUnitManager() || RightsService.isUnitEditor())
              ? DataGridFirstColumn.deleteAndCheck
              : DataGridFirstColumn.check,
      idColumn: TbEshop.orders.id,
      actionsExtended: DataGridActionsController(
        areAllActionsEnabled: () => canSaveOrderGridChanges(
          isOrderEditor: RightsService.isEditorOrder(),
          isUnitManager: RightsService.isUnitManager(),
          isUnitEditor: RightsService.isUnitEditor(),
        ),
        canDeleteRow: (row) =>
            OrderGridFilters.order(row)?.state == OrderModel.stornoState,
        isAddActionPossible: () => false,
      ),
      headerChildren: [
        if (RightsService.isEditorOrder() &&
            forms.any((f) => f.waitlistEnabled))
          sendOffersAction,
        DataGridAction(
          name: CommonStrings.cancel,
          requiresSelection: true,
          action: (SingleDataGridController singleDataGrid, [_]) =>
              cancelOrders(singleDataGrid),
          isEnabled: () =>
              RightsService.isOrderEditor() &&
              (controller?.visibleCheckedRows
                      .every((row) => OrderGridFilters.allows(row, 'cancel')) ??
                  false),
        ),
        DataGridAction(
          name: OrdersStrings.sendActionText,
          requiresSelection: true,
          action: (SingleDataGridController singleDataGrid, [_]) =>
              sendTicketsOrConfirmations(singleDataGrid),
          isEnabled: () =>
              RightsService.isOrderEditor() &&
              (controller?.visibleCheckedRows.every((row) =>
                      OrderGridFilters.allows(row, 'send') ||
                      OrderGridFilters.allows(row, 'paid')) ??
                  false),
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
    if (loadFailed) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(CommonStrings.unexpectedError),
            TextButton(
              onPressed: _initializeController,
              child: Text(CommonStrings.retry),
            ),
          ],
        ),
      );
    }
    if (controller == null) {
      return const Center(child: CircularProgressIndicator());
    }
    return SingleTableDataGrid<OrderModel>(controller!);
  }

  Future<void> cancelOrders(SingleDataGridController singleDataGrid) async {
    var selected = _getChecked(singleDataGrid);
    if (selected.isEmpty || selected.any((o) => !o.allows('cancel'))) {
      return;
    }

    if (selected.isNotEmpty) {
      var confirm = await DataGridActionConfirmation.show<OrderModel>(
        context: context,
        title: CommonStrings.cancel,
        message: OrdersStrings.cancelOrdersConfirmationText,
        items: selected,
        itemsLabel: OrdersStrings.ordersTab,
        confirmButtonText: CommonStrings.cancel,
      );

      if (confirm && mounted) {
        final visibleIds = _getChecked(singleDataGrid).map((o) => o.id).toSet();
        var futures = selected.where((o) => visibleIds.contains(o.id)).map((s) {
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
    if (!mounted) return;
    final currentIds = _getChecked(singleDataGrid).map((o) => o.id).toSet();
    for (var s in selected) {
      if (!currentIds.contains(s.id)) continue;
      var o = ordersBundle.orders.firstWhere((o) => o.id == s.id);
      if (!(o.allows('send') || o.allows('paid'))) return;
      selectedFull.add(o);
    }
    if (selectedFull.isEmpty) return;
    var stateChange =
        selectedFull.where((s) => s.state == OrderModel.orderedState).toList();
    if (stateChange.isNotEmpty) {
      var confirm = await DataGridActionConfirmation.show<OrderModel>(
        context: context,
        title: OrdersStrings.changeStateToPaid,
        message: OrdersStrings.changeStateToPaidConfirmation,
        items: stateChange,
        itemsLabel: OrdersStrings.ordersTab,
        confirmButtonText: OrdersStrings.changeStateToPaid,
      );
      if (!mounted || !confirm) return;

      final visibleIds = _getChecked(singleDataGrid).map((o) => o.id).toSet();
      var futures =
          stateChange.where((o) => visibleIds.contains(o.id)).map((s) {
        return () async {
          await DbOrders.updateOrderAndTicketsToPaid(s.id!);
        };
      }).toList();
      if (futures.isEmpty) return;
      final success = await DialogHelper.showProgressDialogAsync(
          context, OrdersStrings.processing, futures.length,
          futures: futures, isBasic: true);
      if (!success) {
        if (mounted) await refreshData();
        return;
      }
    }

    if (!mounted) return;
    final checkedIds = _getChecked(singleDataGrid).map((o) => o.id).toSet();
    final sending =
        selectedFull.where((o) => checkedIds.contains(o.id)).toList();
    var confirm = await DataGridActionConfirmation.show<OrderModel>(
      context: context,
      title: OrdersStrings.sendActionText,
      message: OrdersStrings.sendActionConfirmationText,
      items: sending,
      itemsLabel: OrdersStrings.ordersTab,
      confirmButtonText: OrdersStrings.sendActionText,
    );

    if (confirm && mounted) {
      final visibleIds = _getChecked(singleDataGrid).map((o) => o.id).toSet();
      var futures = sending.where((o) => visibleIds.contains(o.id)).map((s) {
        return () async {
          await sendTicketsToEmail(s);
        };
      }).toList();

      await DialogHelper.showProgressDialogAsync(
          context, OrdersStrings.processing, futures.length,
          futures: futures);
    }
    if (mounted) await refreshData();
  }

  Future<void> sendTicketsToEmail(OrderModel order) async {
    await DbTickets.sendTicketsToEmail(
      orderId: order.id!,
      email: order.data!["email"],
    );
  }

  List<OrderModel> _getChecked(SingleDataGridController singleDataGrid) {
    return List<OrderModel>.from(
      singleDataGrid.visibleCheckedRows.map((row) =>
          OrderGridFilters.order(row) ??
          OrderModel.fromPlutoJson(row.toJson())),
    );
  }
}
