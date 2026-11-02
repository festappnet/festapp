import 'package:flutter/services.dart';

import 'order_detail_split_pane.dart';
import '../order_detail_strings.dart';

import 'package:fstapp/components/navigation/retained_draft_guard.dart';

import 'dart:convert';

import '../order_detail_controller.dart';
import 'order_detail_view.dart';

import 'package:fstapp/components/navigation/root_route_navigation.dart';
import 'package:fstapp/components/notification_center/notification_detail_target.dart';
import 'package:fstapp/components/navigation/route_visibility.dart';

import 'package:trina_grid/trina_grid.dart';
import 'package:fstapp/data_services/authorization_capabilities.dart';

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

import '../order_cancel_confirmation.dart';

import '../../forms/waitlist_strings.dart';
import '../../forms/views/waitlist_offers_dialog.dart';

import 'package:fstapp/components/eshop/order_grid_filters.dart';
import 'package:material_ui/material_ui.dart';
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
import 'package:auto_route/auto_route.dart';
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
  required bool canWriteOrders,
  required bool canDeleteOrders,
}) => canWriteOrders || canDeleteOrders;

/// Waiting registrations remain available for offers when the Active filter hides them.
List<OrderModel> waitingOrdersForOffers(
  SingleDataGridController grid,
  List<FormBundle> forms,
) => grid.rows
    .map(OrderGridFilters.order)
    .whereType<OrderModel>()
    .where(
      (order) =>
          order.isWaitlisted &&
          order.allows('offer') &&
          (order.waitlistSummary?.counts['waiting'] ?? 0) > 0 &&
          forms.any(
            (form) =>
                form.definition.id == order.formId &&
                form.definition.waitlistEnabled &&
                form.definition.capacity?.canSendOffers == true &&
                form.definition.capacity!.offerablePlaces > 0,
          ),
    )
    .toList();

List<OrderModel> checkedWaitingOrdersForOffers(
  SingleDataGridController grid,
  List<FormBundle> forms,
) {
  final eligible = waitingOrdersForOffers(grid, forms);
  final checked = grid.visibleCheckedRows.map(OrderGridFilters.order).toSet();
  return eligible.where(checked.contains).toList();
}

int availableWaitlistOffers(
  List<FormBundle> forms,
  Iterable<OrderModel> orders,
) {
  var total = 0;
  for (final form in forms) {
    final capacity = form.definition.capacity;
    if (!form.definition.waitlistEnabled || capacity?.canSendOffers != true) {
      continue;
    }
    final waiting = orders
        .where(
          (order) =>
              order.formId == form.definition.id &&
              order.isWaitlisted &&
              order.allows('offer'),
        )
        .fold<int>(
          0,
          (sum, order) => sum + (order.waitlistSummary?.counts['waiting'] ?? 0),
        );
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
    forms,
    grid.rows.map(OrderGridFilters.order).whereType<OrderModel>(),
  );
  if (!RightsService.canUpdateOrders() || count == 0) {
    return const SizedBox.shrink();
  }
  final action = createWaitlistOffersAction(
    context,
    forms: () => forms,
    controller: () => grid,
    onRefresh: onRefresh,
    offerDialogBuilder: offerDialogBuilder,
  );
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
}) => DataGridAction(
  name: WaitlistStrings.send,
  requiresSelection: false,
  isEnabled: () {
    final grid = controller();
    return RightsService.canUpdateOrders() &&
        grid != null &&
        grid.isGridLoaded &&
        !grid.hasUnsavedChanges &&
        availableWaitlistOffers(
              forms(),
              waitingOrdersForOffers(grid, forms()),
            ) >
            0;
  },
  action: (SingleDataGridController grid, [_]) async {
    if (!RightsService.canUpdateOrders() || grid.hasUnsavedChanges) return;
    final checked = checkedWaitingOrdersForOffers(grid, forms());
    final selected = checked.isNotEmpty
        ? checked
        : waitingOrdersForOffers(grid, forms());
    if (selected.isEmpty) return;
    final eligible = forms()
        .where(
          (form) =>
              form.definition.waitlistEnabled &&
              form.definition.capacity?.canSendOffers == true &&
              selected.any((order) => order.formId == form.definition.id),
        )
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
                    child: Text(
                      form.definition.title ?? form.definition.link ?? '',
                    ),
                  ),
              ],
            ),
          );
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
            selectedOrderIds: selectedIds,
          ),
    );
    await onRefresh();
  },
);

// The state class has been renamed accordingly
class _OrdersContentState extends State<OrdersContent> {
  String? occasionLink;
  SingleDataGridController<OrderModel>? controller;
  int? unitId;
  bool loadFailed = false;
  int _formCount = 0;
  int? _openedOrder;
  int? _occasionId;
  OrderDetailController? _detail;
  bool _syncingDetail = false;
  int? _focusedDetailOrder;
  String _lastTab = 'overview';
  bool _escapeClosing = false;
  KeyEventResult _handleDetailEscape(KeyEvent event) {
    if (event is! KeyDownEvent ||
        event.logicalKey != LogicalKeyboardKey.escape ||
        !mounted ||
        _detail == null ||
        _escapeClosing ||
        !isVisibleRouteInstance(context))
      return KeyEventResult.ignored;
    final focusedContext = FocusManager.instance.primaryFocus?.context;
    if (focusedContext != null) {
      final focusedRoute = ModalRoute.of(focusedContext);
      if (focusedRoute != null && focusedRoute != ModalRoute.of(context))
        return KeyEventResult.ignored;
    }
    _escapeClosing = true;
    _closeDetailFromEscape();
    return KeyEventResult.handled;
  }

  Future<void> _closeDetailFromEscape() async {
    try {
      await _navigateDetail(null);
    } finally {
      _escapeClosing = false;
    }
  }

  Future<bool> _allowDetailLeave() async {
    if (_detail?.busy == true) return false;
    if (_detail?.dirty != true) return true;
    final discard =
        await showDialog<bool>(
          context: context,
          builder: (dialogContext) => AppAlertDialog(
            title: Text(OrderDetailStrings.text('unsaved_changes')),
            content: Text(OrderDetailStrings.text('discard_contact_note')),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(dialogContext, false),
                child: Text(OrderDetailStrings.text('continue_editing')),
              ),
              FilledButton(
                onPressed: () => Navigator.pop(dialogContext, true),
                child: Text(OrderDetailStrings.text('discard_changes')),
              ),
            ],
          ),
        ) ==
        true;
    if (discard) _detail?.discardDraft();
    return discard;
  }

  Future<void> _navigateDetail(
    int? id, {
    String? tab,
    int? ticket,
    String? message,
    bool replace = false,
  }) async {
    if (id != _openedOrder && !await _allowDetailLeave()) return;
    if (!mounted) return;
    final root = context.router.root;
    final uri = root.urlState.uri;
    final query = Map<String, String>.from(uri.queryParameters)
      ..remove('orderId')
      ..remove('orderTab')
      ..remove('orderTicketId')
      ..remove('orderMessageId');
    if (id != null) {
      query['orderId'] = '$id';
      if (tab != null && tab != 'overview') query['orderTab'] = tab;
      if (ticket != null) query['orderTicketId'] = '$ticket';
      if (message != null) query['orderMessageId'] = message;
    }
    if (replace) root.markUrlStateForReplace();
    await root.navigate(
      rootRouteForPath(root, uri.replace(queryParameters: query).toString()),
    );
    if (mounted) _syncDetailTarget();
  }

  void _focusInitialDetailRow(int? id) {
    final grid = controller;
    if (id == null || id == _focusedDetailOrder || grid?.isGridLoaded != true)
      return;
    final manager = grid!.stateManager;
    if (manager.gridFocusNode.context
            ?.findAncestorWidgetOfExactType<Offstage>()
            ?.offstage ==
        true)
      return;
    final rows = manager.refRows.filterOrOriginalList;
    final index = rows.indexWhere(
      (row) => OrderGridFilters.order(row)?.id == id,
    );
    if (index < 0)
      return; // A deep link does not silently discard table filters.
    _focusedDetailOrder = id;
    manager.setKeepFocus(true);
    manager.setCurrentCell(
      rows[index].cells[EshopColumnIds.ORDER_SYMBOL],
      index,
    );
    manager.moveScrollByRow(TrinaMoveDirection.down, index);
  }

  Future<void> _syncDetailTarget() async {
    if (_occasionId == null || _syncingDetail || !mounted) return;
    final query = context.router.root.urlState.uri.queryParameters;
    final id = int.tryParse(query['orderId'] ?? '');
    _lastTab =
        query['orderTab'] ??
        (query['orderMessageId'] != null ? 'emails' : 'overview');
    if (id == _openedOrder) {
      controller?.activeDetailRowId.value = id;
      _focusInitialDetailRow(id);
      if (mounted) setState(() {});
      return;
    }
    _syncingDetail = true;
    if (!await _allowDetailLeave()) {
      _syncingDetail = false;
      if (mounted)
        await _navigateDetail(_openedOrder, tab: _lastTab, replace: true);
      return;
    }
    if (!mounted) {
      _syncingDetail = false;
      return;
    }
    final latest = int.tryParse(
      context.router.root.urlState.uri.queryParameters['orderId'] ?? '',
    );
    if (latest != id) {
      _syncingDetail = false;
      _detailRouteChanged();
      return;
    }
    final previous = _detail;
    _detail = id == null
        ? null
        : OrderDetailController(orderId: id, occasionId: _occasionId!);
    _openedOrder = id;
    _focusedDetailOrder = null;
    controller?.activeDetailRowId.value = id;
    _focusInitialDetailRow(id);
    previous?.dispose();
    _syncingDetail = false;
    if (mounted) setState(() {});
    await _detail?.load();
  }

  StackRouter? _detailRouter;
  bool _routeSyncScheduled = false;
  void _detailRouteChanged() {
    if (_routeSyncScheduled || !mounted) return;
    _routeSyncScheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _routeSyncScheduled = false;
      if (mounted && isVisibleRouteInstance(context)) _syncDetailTarget();
    });
  }

  int _loadGeneration = 0;

  @override
  void initState() {
    super.initState();
    FocusManager.instance.addLateKeyEventHandler(_handleDetailEscape);
    DbBankAccounts.current.connectionChanges.addListener(
      _bankConnectionChanged,
    );
  }

  Future<void> _bankConnectionChanged() async {
    final grid = controller;
    final id = DbBankAccounts.current.connectionChanges.value.accountId;
    if (!mounted ||
        grid == null ||
        !grid.rows.any(
          (row) =>
              OrderGridFilters.order(row)?.paymentInfoModel?.bankAccount == id,
        ))
      return;
    try {
      await grid.reloadIfClean(
        canApply: () => mounted && identical(grid, controller),
      );
    } catch (error) {
      AppLogger.error('Could not refresh bank-linked orders: $error');
    }
  }

  @override
  void dispose() {
    FocusManager.instance.removeLateKeyEventHandler(_handleDetailEscape);
    _detailRouter?.removeListener(_detailRouteChanged);
    DbBankAccounts.current.connectionChanges.removeListener(
      _bankConnectionChanged,
    );
    _detail?.dispose();
    super.dispose();
  }

  String? _selectedNotificationGroup;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final root = context.router.root;
    if (_detailRouter != root) {
      _detailRouter?.removeListener(_detailRouteChanged);
      _detailRouter = root;
      root.addListener(_detailRouteChanged);
    }
    final newOccasionLink = context.routeData.inheritedPathParams.getString(
      AppRouter.linkFormatted,
    );
    // Initialize only once when the link is available
    if (occasionLink == null) {
      occasionLink = newOccasionLink;
      _initializeController();
    } else {
      final group = context.routeData.queryParams.optString(
        'notificationGroup',
      );
      if (group != null && group != _selectedNotificationGroup)
        _initializeController();
      WidgetsBinding.instance.addPostFrameCallback((_) => _syncDetailTarget());
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

    final generation = ++_loadGeneration;
    final groupTarget = context.routeData.queryParams.optString(
      'notificationGroup',
    );
    final group = groupTarget == null
        ? null
        : jsonDecode(groupTarget) as Map<String, dynamic>;
    // Resolve notification selection in the existing orders request.
    final occasion = RightsService.currentOccasion();
    if (occasion?.id == null ||
        RightsService.currentOccasionId() != occasion!.id) {
      throw StateError('Order context unavailable');
    }
    var bundle = await DbOrders.getOrdersTabData(
      occasionLink: occasionLink!,
      notificationGroup: group,
    );
    unitId = RightsService.currentUnit()?.id ?? occasion.unit;
    _occasionId = occasion.id;

    if (!mounted || generation != _loadGeneration) return;

    var forms = bundle.forms;
    _formCount = forms.length;
    bool waitlistEnabled() =>
        forms.any((form) => form.definition.waitlistEnabled);
    void updateWaitlistColumn(SingleDataGridController<OrderModel> grid) {
      final column = grid.columns.firstWhere(
        (column) => column.field == EshopColumnIds.ORDER_WAITLIST,
      );
      if (grid.isGridLoaded) {
        grid.stateManager.hideColumn(column, !waitlistEnabled());
      } else {
        column.hide = !waitlistEnabled();
      }
    }

    void fitStateColumn(
      SingleDataGridController<OrderModel> grid,
      List<OrderModel> orders,
    ) {
      final column = grid.columns.firstWhere(
        (column) => column.field == EshopColumnIds.ORDER_STATE,
      );
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
    final hasOrderNoteField = forms.any(
      (form) => (form.definition.relatedFields).any(
        (field) =>
            field.type == FormMetadata.fieldTypeNote &&
            (field.isTicketField ?? false) == false,
      ),
    );

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
    ];

    // Conditionally add the form column if there are multiple forms
    if (forms.length > 1) {
      final symbolIndex = columnIdentifiers.indexOf(
        EshopColumnIds.ORDER_SYMBOL,
      );
      columnIdentifiers.insert(symbolIndex + 1, EshopColumnIds.ORDER_FORM);
    }

    // Create the controller with the final column list
    List<OrderModel>? firstLoadOrders = bundle.orders;

    final sendOffersAction = DataGridAction(
      name: WaitlistStrings.send,
      requiresSelection: false,
      action: (SingleDataGridController singleDataGrid, [_]) async {
        final eligible = forms
            .where((f) => f.definition.waitlistEnabled)
            .toList();
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
                        child: Text(
                          f.definition.title ?? f.definition.link ?? '',
                        ),
                      ),
                  ],
                ),
              );
        if (chosen == null || !mounted) return;
        await showDialog(
          context: context,
          builder: (_) =>
              WaitlistOffersDialog(form: chosen, orders: bundle.orders),
        );
        await refreshData();
      },
      isEnabled: RightsService.canUpdateOrders,
    );

    final newController = SingleDataGridController<OrderModel>(
      onRowActivate: (order) => _navigateDetail(order.id),
      prepareDeletion: prepareOrderDeletion,
      columnHelp: {
        EshopColumnIds.PAYMENT_INFO_RETURNED: OrdersStrings.gridReturnedHelp,
      },
      context: context,
      additionalFilterEnabled: true,
      additionalRowPredicate: OrderGridFilters.orderIsActive,
      headerFilterBuilder: (context, grid) => Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          OrderGridFilters.filterButton(
            context,
            grid,
            label: WaitlistStrings.text('active'),
          ),
          waitlistOffersToolbarButton(
            context,
            grid,
            forms: forms,
            onRefresh: refreshData,
          ),
        ],
      ),
      loadData: () async {
        if (firstLoadOrders != null) {
          final orders = firstLoadOrders;
          firstLoadOrders =
              null; // Clear it so subsequent reloads fetch fresh data
          return orders!;
        }
        final newBundle = await DbOrders.getOrdersTabData(
          occasionLink: occasionLink!,
        );
        bundle = newBundle;
        forms = newBundle.forms;
        _formCount = forms.length;
        final actions = controller?.headerChildren;
        actions?.removeWhere((action) => identical(action, sendOffersAction));
        if (RightsService.canUpdateOrders() &&
            forms.any((f) => f.definition.waitlistEnabled)) {
          actions?.insert(0, sendOffersAction);
        }
        return newBundle.orders;
      },
      fromPlutoJson: OrderModel.fromPlutoJson,
      firstColumnType:
          RightsService.hasCapability(AuthorizationCapabilities.ordersDelete)
          ? DataGridFirstColumn.deleteAndCheck
          : DataGridFirstColumn.check,
      idColumn: TbEshop.orders.id,
      actionsExtended: DataGridActionsController(
        areAllActionsEnabled: () => canSaveOrderGridChanges(
          canWriteOrders: RightsService.canUpdateOrders(),
          canDeleteOrders: RightsService.hasCapability(
            AuthorizationCapabilities.ordersDelete,
          ),
        ),
        canDeleteRow: OrderGridFilters.orderCanBeDeleted,
        isAddActionPossible: () => false,
      ),
      headerChildren: [
        if (RightsService.canUpdateOrders() &&
            forms.any((f) => f.definition.waitlistEnabled))
          sendOffersAction,
        DataGridAction(
          name: OrderItemStrings.cancelAction,
          requiresSelection: true,
          action: (SingleDataGridController singleDataGrid, [_]) =>
              cancelOrders(singleDataGrid),
          isEnabled: () =>
              RightsService.canUpdateOrders() &&
              (controller?.visibleCheckedRows.every(
                    (row) => OrderGridFilters.allows(row, 'cancel'),
                  ) ??
                  false),
        ),
        DataGridAction(
          name: OrderItemStrings.sendActionText,
          requiresSelection: true,
          action: (SingleDataGridController singleDataGrid, [_]) =>
              sendTicketsOrConfirmations(singleDataGrid),
          isEnabled: () =>
              RightsService.canUpdateOrders() &&
              (controller?.visibleCheckedRows.every(
                    (row) =>
                        OrderGridFilters.allows(row, 'send') ||
                        OrderGridFilters.allows(row, 'paid'),
                  ) ??
                  false),
        ),
      ],
      columns: EshopColumns.generateColumns(
        context,
        columnIdentifiers,
        data: {
          EshopColumnIds.ORDER_TRANSACTIONS: refreshData,
          EshopColumnIds.ORDER_STATE: refreshData,
          EshopColumnIds.PAYMENT_INFO_PAID: refreshData,
          "unitId": unitId,
          "occasionId": occasion.id,
          "openOrderDetail": (int id, String tab) =>
              _navigateDetail(id, tab: tab),
        },
      ),
    );

    for (final column in newController.columns) {
      if (column.field == EshopColumnIds.ORDER_DATA) {
        column.readOnly = true;
        column.enableEditingMode = false;
      }
    }
    updateWaitlistColumn(newController);
    fitStateColumn(newController, bundle.orders);
    if (mounted) {
      setState(() {
        controller = newController;
      });
      _selectedNotificationGroup = groupTarget;
      if (groupTarget != null) {
        WidgetsBinding.instance.addPostFrameCallback(
          (_) => _selectNotificationOrders(
            newController,
            bundle.notificationOrderIds,
            groupTarget,
            generation,
          ),
        );
      }
      WidgetsBinding.instance.addPostFrameCallback((_) async {
        // The query detail may arrive before Trina creates its manager. Rebuild
        // once it is ready so the detail observes real filtered rows, not an
        // empty startup list or the temporary readiness notifier.
        if (!await newController.whenLoaded ||
            !mounted ||
            generation != _loadGeneration ||
            !identical(controller, newController))
          return;
        setState(() {});
        await _syncDetailTarget();
      });
    }
  }

  void _revealNotificationOrders(
    SingleDataGridController<OrderModel> grid,
    Set<int> ids,
  ) {
    // Keep Active unless a selected order needs the broader view.
    final hasInactiveOrder = grid.stateManager.refRows.originalList.any(
      (row) =>
          ids.contains(OrderGridFilters.order(row)?.id) &&
          !OrderGridFilters.orderIsActive(row),
    );
    grid.stateManager.setFilterRows([]);
    grid.additionalFilterEnabled = !hasInactiveOrder;
    grid.applyRowFilter();
  }

  Future<void> _selectNotificationOrders(
    SingleDataGridController<OrderModel> grid,
    Set<int> ids,
    String target,
    int generation,
  ) async {
    bool owns() =>
        mounted &&
        generation == _loadGeneration &&
        identical(grid, controller) &&
        isVisibleRouteInstance(context) &&
        context.routeData.queryParams.optString('notificationGroup') == target;
    if (!await grid.whenLoaded) return;
    await WidgetsBinding.instance.endOfFrame;
    if (!mounted || !owns() || !grid.isGridLoaded) return;
    _revealNotificationOrders(grid, ids);
    final manager = grid.stateManager;
    manager.setSelectingMode(TrinaGridSelectingMode.row, notify: false);
    manager.clearCurrentSelecting(notify: false);
    final rows = manager.refRows.filterOrOriginalList;
    final index = rows.indexWhere(
      (row) => ids.contains(OrderGridFilters.order(row)?.id),
    );
    if (index >= 0) {
      manager.setCurrentCell(
        rows[index].cells[EshopColumnIds.ORDER_SYMBOL],
        index,
        notify: false,
      );
      for (var i = 0; i < rows.length; i++) {
        if (ids.contains(OrderGridFilters.order(rows[i])?.id)) {
          manager.toggleSelectingRow(i, notify: false);
        }
      }
      manager.moveScrollByRow(TrinaMoveDirection.down, index);
    }
    manager.notifyListeners();
    if (owns()) {
      _selectedNotificationGroup = null;
      await clearNotificationDetailTarget(context, 'notificationGroup', target);
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
    final grid = SingleTableDataGrid<OrderModel>(
      controller!,
      onEscape: () {
        if (_detail != null) _navigateDetail(null);
      },
      key: ObjectKey(controller),
      emptyMessage: OrdersStrings.noOrders,
    );
    final active = _detail;
    final query = context.router.root.urlState.uri.queryParameters;
    return NavigationDraftBoundary(
      isDirty: () => _detail?.dirty == true || _detail?.busy == true,
      confirm: _allowDetailLeave,
      child: OrderDetailSplitPane(
        table: grid,
        detail: active == null
            ? null
            : ListenableBuilder(
                listenable: controller!.isGridLoaded
                    ? controller!.stateManager
                    : controller!.refreshKeyNotifier,
                builder: (context, _) {
                  final rows = controller!.isGridLoaded
                      ? controller!.stateManager.refRows.filterOrOriginalList
                      : <TrinaRow>[];
                  final ids = rows
                      .map((r) => OrderGridFilters.order(r)?.id)
                      .whereType<int>()
                      .toList();
                  final index = ids.indexOf(_openedOrder ?? -1);
                  return OrderDetailView(
                    key: ObjectKey(active),
                    controller: active,
                    formCount: _formCount,
                    tab:
                        query['orderTab'] ??
                        (query['orderMessageId'] != null
                            ? 'emails'
                            : 'overview'),
                    messageId: query['orderMessageId'],
                    ticketId: int.tryParse(query['orderTicketId'] ?? ''),
                    outsideFilter: controller!.isGridLoaded && index < 0,
                    onReveal: () {
                      _revealNotificationOrders(controller!, {active.orderId});
                      final rows =
                          controller!.stateManager.refRows.filterOrOriginalList;
                      final i = rows.indexWhere(
                        (r) => OrderGridFilters.order(r)?.id == active.orderId,
                      );
                      if (i >= 0) {
                        controller!.stateManager.setCurrentCell(
                          rows[i].cells[EshopColumnIds.ORDER_SYMBOL],
                          i,
                        );
                        controller!.stateManager.moveScrollByRow(
                          TrinaMoveDirection.down,
                          i,
                        );
                      }
                      setState(() {});
                    },
                    onTab: (tab) => _navigateDetail(
                      active.orderId,
                      tab: tab,
                      replace: true,
                    ),
                    onTicket: (id) => _navigateDetail(
                      active.orderId,
                      tab: 'tickets',
                      ticket: id,
                      replace: true,
                    ),
                    onPrevious: index > 0
                        ? () => _navigateDetail(
                            ids[index - 1],
                            tab: _lastTab,
                            replace: true,
                          )
                        : null,
                    onNext: index >= 0 && index < ids.length - 1
                        ? () => _navigateDetail(
                            ids[index + 1],
                            tab: _lastTab,
                            replace: true,
                          )
                        : null,
                    onClose: () => _navigateDetail(null, replace: true),
                    onChanged: () async {
                      await controller?.reloadIfClean();
                      if (mounted) setState(() {});
                    },
                  );
                },
              ),
      ),
    );
  }

  Future<void> cancelOrders(SingleDataGridController singleDataGrid) async {
    var selected = _getChecked(singleDataGrid);
    if (selected.isEmpty || selected.any((o) => !o.allows('cancel'))) {
      return;
    }

    if (selected.isNotEmpty) {
      var confirm = await confirmOrderCancellation(context, selected);

      if (confirm && mounted) {
        final visibleIds = _getChecked(singleDataGrid).map((o) => o.id).toSet();
        var futures = selected.where((o) => visibleIds.contains(o.id)).map((s) {
          return () async {
            await DbOrders.stornoOrder(s.id!);
          };
        }).toList();

        await DialogHelper.showProgressDialogAsync(
          context,
          OrdersStrings.processing,
          futures.length,
          futures: futures,
        );
        refreshData();
      }
    }
  }

  Future<void> sendTicketsOrConfirmations(
    SingleDataGridController singleDataGrid,
  ) async {
    if (occasionLink == null) return;
    var selected = _getChecked(singleDataGrid);
    if (selected.isEmpty) {
      return;
    }

    List<OrderModel> selectedFull = [];

    var ordersBundle = await DbOrders.getAllOrdersBundle(
      occasionLink: occasionLink!,
    );
    if (!mounted) return;
    final currentIds = _getChecked(singleDataGrid).map((o) => o.id).toSet();
    for (var s in selected) {
      if (!currentIds.contains(s.id)) continue;
      var o = ordersBundle.orders.firstWhere((o) => o.id == s.id);
      if (!(o.allows('send') || o.allows('paid'))) return;
      selectedFull.add(o);
    }
    if (selectedFull.isEmpty) return;
    var stateChange = selectedFull
        .where((s) => s.state == OrderModel.orderedState)
        .toList();
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
      var futures = stateChange.where((o) => visibleIds.contains(o.id)).map((
        s,
      ) {
        return () async {
          await DbOrders.updateOrderAndTicketsToPaid(s.id!);
        };
      }).toList();
      if (futures.isEmpty) return;
      final success = await DialogHelper.showProgressDialogAsync(
        context,
        OrdersStrings.processing,
        futures.length,
        futures: futures,
        isBasic: true,
      );
      if (!success) {
        if (mounted) await refreshData();
        return;
      }
    }

    if (!mounted) return;
    final checkedIds = _getChecked(singleDataGrid).map((o) => o.id).toSet();
    final sending = selectedFull
        .where((o) => checkedIds.contains(o.id))
        .toList();
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
          await sendTicketsToEmail(
            s,
            firstDelivery: newlyPaidIds.contains(s.id),
          );
        };
      }).toList();

      await DialogHelper.showProgressDialogAsync(
        context,
        OrdersStrings.processing,
        futures.length,
        futures: futures,
      );
    }
    if (mounted) await refreshData();
  }

  Future<void> sendTicketsToEmail(
    OrderModel order, {
    bool firstDelivery = false,
  }) async {
    await DbTickets.sendTicketsToEmail(
      orderId: order.id!,
      email: order.data!["email"],
      firstDelivery: firstDelivery,
    );
  }

  List<OrderModel> _getChecked(SingleDataGridController singleDataGrid) {
    return List<OrderModel>.from(
      singleDataGrid.visibleCheckedRows.map(
        (row) =>
            OrderGridFilters.order(row) ??
            OrderModel.fromPlutoJson(row.toJson()),
      ),
    );
  }
}
