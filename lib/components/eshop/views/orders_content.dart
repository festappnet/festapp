import 'order_delete_dialog.dart';
import 'package:fstapp/components/bank_accounts/db_bank_accounts.dart';
import 'package:fstapp/services/app_logger.dart';
import 'order_state_column_width.dart';
import 'package:fstapp/components/eshop/order_item_strings.dart';
import 'package:fstapp/components/eshop/eshop_column_ids.dart';
import 'package:festapp_core/forms.dart';
import 'package:fstapp/components/forms/models/form_bundle.dart';
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

/// Waiting registrations remain available for offers when the Active filter hides them.
List<OrderModel> waitingOrdersForOffers(
        SingleDataGridController grid, List<FormBundle> forms) =>
    grid.rows
        .map(OrderGridFilters.order)
        .whereType<OrderModel>()
        .where((order) =>
            order.isWaitlisted &&
            order.allows('offer') &&
            (order.waitlistSummary?.counts['waiting'] ?? 0) > 0 &&
            forms.any((form) =>
                form.definition.id == order.formId &&
                form.definition.waitlistEnabled &&
                form.definition.capacity?.canSendOffers == true &&
                form.definition.capacity!.offerablePlaces > 0))
        .toList();

List<OrderModel> checkedWaitingOrdersForOffers(
    SingleDataGridController grid, List<FormBundle> forms) {
  final eligible = waitingOrdersForOffers(grid, forms);
  final checked = grid.visibleCheckedRows.map(OrderGridFilters.order).toSet();
  return eligible.where(checked.contains).toList();
}

int availableWaitlistOffers(
    List<FormBundle> forms, Iterable<OrderModel> orders) {
  var total = 0;
  for (final form in forms) {
    final capacity = form.definition.capacity;
    if (!form.definition.waitlistEnabled || capacity?.canSendOffers != true) {
      continue;
    }
    final waiting = orders
        .where((order) =>
            order.formId == form.definition.id &&
            order.isWaitlisted &&
            order.allows('offer'))
        .fold<int>(
            0,
            (sum, order) =>
                sum + (order.waitlistSummary?.counts['waiting'] ?? 0));
    final available = capacity!.offerablePlaces;
    total += waiting < available ? waiting : available;
  }
  return total;
}

Widget waitlistOffersToolbarButton(
  BuildContext context,
  SingleDataGridController<OrderModel> grid, {
  required List<FormBundle> forms,
  required Future<void> Function() onRefresh,
  Widget Function(FormBundle, List<OrderModel>, Set<int>)? offerDialogBuilder,
}) {
  final count = availableWaitlistOffers(
      forms, grid.rows.map(OrderGridFilters.order).whereType<OrderModel>());
  if (!RightsService.isEditorOrder() || count == 0) {
    return const SizedBox.shrink();
  }
  final action = createWaitlistOffersAction(context,
      forms: () => forms,
      controller: () => grid,
      onRefresh: onRefresh,
      offerDialogBuilder: offerDialogBuilder);
  return Padding(
    padding: const EdgeInsetsDirectional.only(start: 8),
    child: ElevatedButton(
      onPressed: action.isEnabled!() ? () => action.action!(grid, null) : null,
      child: Text('${WaitlistStrings.send} ($count)'),
    ),
  );
}

/// The grid and widget tests use the same selection and canonical offer orchestration.
DataGridAction createWaitlistOffersAction(
  BuildContext context, {
  required List<FormBundle> Function() forms,
  required SingleDataGridController<OrderModel>? Function() controller,
  required Future<void> Function() onRefresh,
  Widget Function(FormBundle, List<OrderModel>, Set<int>)? offerDialogBuilder,
}) =>
    DataGridAction(
      name: WaitlistStrings.send,
      requiresSelection: false,
      isEnabled: () {
        final grid = controller();
        return RightsService.isEditorOrder() &&
            grid != null &&
            grid.isGridLoaded &&
            !grid.hasUnsavedChanges &&
            availableWaitlistOffers(
                    forms(), waitingOrdersForOffers(grid, forms())) >
                0;
      },
      action: (SingleDataGridController grid, [_]) async {
        if (!RightsService.isEditorOrder() || grid.hasUnsavedChanges) return;
        final checked = checkedWaitingOrdersForOffers(grid, forms());
        final selected = checked.isNotEmpty
            ? checked
            : waitingOrdersForOffers(grid, forms());
        if (selected.isEmpty) return;
        final eligible = forms()
            .where((form) =>
                form.definition.waitlistEnabled &&
                form.definition.capacity?.canSendOffers == true &&
                selected.any((order) => order.formId == form.definition.id))
            .toList();
        final chosen = eligible.length == 1
            ? eligible.first
            : await showDialog<FormBundle>(
                context: context,
                builder: (context) => AppSimpleDialog(
                        title: Text(WaitlistStrings.settings),
                        children: [
                          for (final form in eligible)
                            SimpleDialogOption(
                                onPressed: () => Navigator.pop(context, form),
                                child: Text(form.definition.title ??
                                    form.definition.link ??
                                    '')),
                        ]));
        if (chosen == null || !context.mounted) return;
        final recipients = selected
            .where((order) => order.formId == chosen.definition.id)
            .toList();
        final selectedIds = recipients.map((order) => order.id!).toSet();
        await showDialog(
            context: context,
            builder: (_) =>
                offerDialogBuilder?.call(chosen, recipients, selectedIds) ??
                WaitlistOffersDialog(
                    form: chosen,
                    orders: recipients,
                    selectedOrderIds: selectedIds));
        await onRefresh();
      },
    );

// The state class has been renamed accordingly
class _OrdersContentState extends State<OrdersContent> {
  String? occasionLink;
  SingleDataGridController<OrderModel>? controller;
  int? unitId;
  bool loadFailed = false;

  @override
  void initState() {
    super.initState();
    DbBankAccounts.current.connectionChanges
        .addListener(_bankConnectionChanged);
  }

  Future<void> _bankConnectionChanged() async {
    final grid = controller;
    final id = DbBankAccounts.current.connectionChanges.value.accountId;
    if (!mounted ||
        grid == null ||
        !grid.rows.any((row) =>
            OrderGridFilters.order(row)?.paymentInfoModel?.bankAccount == id))
      return;
    try {
      await grid.reloadIfClean(
          canApply: () => mounted && identical(grid, controller));
    } catch (error) {
      AppLogger.error('Could not refresh bank-linked orders: $error');
    }
  }

  @override
  void dispose() {
    DbBankAccounts.current.connectionChanges
        .removeListener(_bankConnectionChanged);
    super.dispose();
  }

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
    bool waitlistEnabled() =>
        forms.any((form) => form.definition.waitlistEnabled);
    void updateWaitlistColumn(SingleDataGridController<OrderModel> grid) {
      final column = grid.columns.firstWhere(
          (column) => column.field == EshopColumnIds.ORDER_WAITLIST);
      if (grid.isGridLoaded) {
        grid.stateManager.hideColumn(column, !waitlistEnabled());
      } else {
        column.hide = !waitlistEnabled();
      }
    }

    void fitStateColumn(
        SingleDataGridController<OrderModel> grid, List<OrderModel> orders) {
      final column = grid.columns
          .firstWhere((column) => column.field == EshopColumnIds.ORDER_STATE);
      final requiredWidth = orderStateColumnWidth(context, orders);
      column.minWidth = requiredWidth;
      if (column.width >= requiredWidth) return;
      if (grid.isGridLoaded) {
        grid.stateManager.resizeColumn(column, requiredWidth - column.width);
      } else {
        column.width = requiredWidth;
      }
    }

    // Check if any field across all forms is a non-ticket 'note' field.
    final hasOrderNoteField = forms.any((form) =>
        (form.definition.relatedFields).any((field) =>
            field.type == FormMetadata.fieldTypeNote &&
            (field.isTicketField ?? false) == false));

    var formFeat =
        FeatureService.getFeatureDetails(FeatureConstants.form) as FormFeature?;

    // Start with the base list of columns
    List<String> columnIdentifiers = [
      EshopColumnIds.ORDER_ID,
      EshopColumnIds.ORDER_SEQUENCE,
      EshopColumnIds.ORDER_SYMBOL,
      EshopColumnIds.ORDER_DATA,
      EshopColumnIds.ORDER_EMAIL,
      if (!FeatureService.isFeatureEnabled(FeatureConstants.ticket))
        EshopColumnIds.TICKET_PRODUCTS,
      EshopColumnIds.ORDER_CREATED_AT,
      EshopColumnIds.ORDER_STATE,
      EshopColumnIds.ORDER_WAITLIST,
      if (FeatureService.isFeatureEnabled(FeatureConstants.contract))
        EshopColumnIds.ORDER_CONTRACT_DOWNLOAD,
      EshopColumnIds.ORDER_PRICE,
      EshopColumnIds.PAYMENT_INFO_PAID,
      EshopColumnIds.PAYMENT_INFO_RETURNED,
      EshopColumnIds.PAYMENT_INFO_VARIABLE_SYMBOL,
      if (hasOrderNoteField) EshopColumnIds.ORDER_DATA_NOTE,
      EshopColumnIds.ORDER_NOTE_HIDDEN,
      if (formFeat?.isEnabled == true && (formFeat?.reminderIsEnabled ?? false))
        EshopColumnIds.PAYMENT_INFO_REMINDER_SENT,
      EshopColumnIds.PAYMENT_INFO_DEADLINE,
      if (FeatureService.isFeatureEnabled(FeatureConstants.deposit))
        EshopColumnIds.PAYMENT_INFO_DEPOSIT_DEADLINE,
      EshopColumnIds.ORDER_EMAIL_DELIVERY,
      EshopColumnIds.ORDER_TRANSACTIONS,
      EshopColumnIds.ORDER_OVERVIEW,
      EshopColumnIds.ORDER_HISTORY,
    ];

    // Conditionally add the form column if there are multiple forms
    if (forms.length > 1) {
      final symbolIndex =
          columnIdentifiers.indexOf(EshopColumnIds.ORDER_SYMBOL);
      columnIdentifiers.insert(symbolIndex + 1, EshopColumnIds.ORDER_FORM);
    }

    // Create the controller with the final column list
    List<OrderModel>? firstLoadOrders = bundle.orders;

    final sendOffersAction = DataGridAction(
      name: WaitlistStrings.send,
      requiresSelection: false,
      action: (SingleDataGridController singleDataGrid, [_]) async {
        final eligible =
            forms.where((f) => f.definition.waitlistEnabled).toList();
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
                              child: Text(f.definition.title ??
                                  f.definition.link ??
                                  ''))
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
      prepareDeletion: prepareOrderDeletion,
      columnHelp: {
        EshopColumnIds.PAYMENT_INFO_RETURNED: OrdersStrings.gridReturnedHelp
      },
      context: context,
      additionalFilterEnabled: true,
      additionalRowPredicate: OrderGridFilters.orderIsActive,
      headerFilterBuilder: (context, grid) => Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          OrderGridFilters.filterButton(context, grid,
              label: WaitlistStrings.text('active')),
          waitlistOffersToolbarButton(context, grid,
              forms: forms, onRefresh: refreshData),
        ],
      ),
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
            forms.any((f) => f.definition.waitlistEnabled)) {
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
        canDeleteRow: OrderGridFilters.orderCanBeDeleted,
        isAddActionPossible: () => false,
      ),
      headerChildren: [
        if (RightsService.isEditorOrder() &&
            forms.any((f) => f.definition.waitlistEnabled))
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
          name: OrderItemStrings.sendActionText,
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
        EshopColumnIds.ORDER_TRANSACTIONS: refreshData,
        EshopColumnIds.PAYMENT_INFO_PAID: refreshData,
        "unitId": unitId,
      }),
    );

    updateWaitlistColumn(newController);
    fitStateColumn(newController, bundle.orders);
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
    return SingleTableDataGrid<OrderModel>(controller!,
        emptyMessage: OrdersStrings.noOrders);
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
        message: OrderItemStrings.cancelOrdersConfirmationText,
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
    // First Send after marking paid uses this payment generation, not a resend.
    final newlyPaidIds = stateChange.map((order) => order.id).toSet();
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
      title: OrderItemStrings.sendActionText,
      message: OrderItemStrings.sendActionConfirmationText,
      items: sending,
      itemsLabel: OrdersStrings.ordersTab,
      confirmButtonText: OrderItemStrings.sendActionText,
    );

    if (confirm && mounted) {
      final visibleIds = _getChecked(singleDataGrid).map((o) => o.id).toSet();
      var futures = sending.where((o) => visibleIds.contains(o.id)).map((s) {
        return () async {
          await sendTicketsToEmail(s,
              firstDelivery: newlyPaidIds.contains(s.id));
        };
      }).toList();

      await DialogHelper.showProgressDialogAsync(
          context, OrdersStrings.processing, futures.length,
          futures: futures);
    }
    if (mounted) await refreshData();
  }

  Future<void> sendTicketsToEmail(OrderModel order,
      {bool firstDelivery = false}) async {
    await DbTickets.sendTicketsToEmail(
      orderId: order.id!,
      email: order.data!["email"],
      firstDelivery: firstDelivery,
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
