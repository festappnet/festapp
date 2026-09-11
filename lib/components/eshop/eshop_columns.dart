import 'package:easy_localization/easy_localization.dart';
import 'package:file_saver/file_saver.dart'; // Added for file saving
import 'package:fstapp/components/_shared/common_strings.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:fstapp/components/inventory/models/inventory_context_model.dart';
import 'package:fstapp/components/inventory/views/inventory_strings.dart';
import 'package:fstapp/components/single_data_grid/data_grid_helper.dart';
import 'package:fstapp/components/forms/models/form_field_model.dart';
import 'package:fstapp/components/eshop/models/order_model.dart';
import 'package:fstapp/components/eshop/models/product_model.dart';
import 'package:fstapp/components/eshop/views/products_dialog.dart';
import 'package:fstapp/components/eshop/views/transactions_dialog.dart';
import 'package:fstapp/components/forms/widgets_view/form_helper.dart';
import 'package:fstapp/components/eshop/db_tickets.dart';
import 'package:fstapp/components/eshop/db_orders.dart';
import 'package:fstapp/components/eshop/db_eshop.dart';
import 'package:fstapp/services/dialog_helper.dart';
import 'package:fstapp/services/toast_helper.dart';
import 'package:fstapp/theme_config.dart';
import 'package:fstapp/data_services/rights_service.dart';
import 'package:trina_grid/trina_grid.dart';
import 'package:fstapp/components/features/feature_constants.dart';
import 'package:fstapp/components/features/feature_service.dart';
import 'views/deposit_renderer.dart';
import 'views/inventory_inclusion_renderer.dart';
import 'models/orders_history_model.dart';
import 'orders_strings.dart';
import 'views/order_history_dialog.dart';
import 'views/order_state_display.dart';
import 'package:fstapp/components/features/features_strings.dart';
import 'package:fstapp/components/eshop/views/search_transactions_dialog.dart';
import 'views/add_cash_payment_dialog.dart';

bool canToggleTicketUsage(String? formattedState) =>
    formattedState?.split(';').first != OrderModel.stornoState;

class EshopColumns {
  // Column identifier constants
  static const String TICKET_ID = "ticketId";
  static const String TICKET_SYMBOL = "ticketSymbol";
  static const String TICKET_STATE = "ticketState";
  static const String TICKET_DOWNLOAD = "ticketDownload"; // New Constant
  static const String TICKET_NOTE = "ticketNote";
  static const String TICKET_NOTE_HIDDEN = "ticketNoteHidden";
  static const String TICKET_TOTAL_PRICE = "ticketTotalPrice";
  static const String TICKET_PRODUCTS = "ticketProducts";
  static const String TICKET_PRODUCTS_EXTENDED = "ticketProductsExtended";
  static const String TICKET_PRODUCTS_EDIT = "ticketProductsEdit";
  static const String TICKET_CONFIRM = "confirmTicket";

  static const String TICKET_CREATED_AT = "ticketCreatedAt";
  static const String TICKET_LAST_CHANGE = "ticketLastChangedAt";
  static const String TICKET_SPOT = "ticketSpot";

  static const String ORDER_ID = "orderId";
  static const String ORDER_PRICE = "orderPrice";
  static const String ORDER_STATE = "orderState";
  static const String ORDER_MODEL_REFERENCE = "orderModelReference";

  static const String PRODUCT_ID = "productId";
  static const String PRODUCT_TITLE = "productTitle";
  static const String PRODUCT_SHORT_TITLE = "productShortTitle";
  static const String PRODUCT_PRICE = "productPrice";
  static const String PRODUCT_IS_HIDDEN = "productIsHidden";
  static const String PRODUCT_TYPE = "productType";
  static const String PRODUCT_ORDER = "productOrder";
  static const String PRODUCT_MAXIMUM = "productMaximum";
  static const String PRODUCT_ORDERED_COUNT = "productOrderedCount";
  static const String PRODUCT_PAID_COUNT = "productPaidCount";
  static const String PRODUCT_CURRENCY_CODE = "productCurrencyCode";
  static const String PRODUCT_DESCRIPTION = "productDescription";
  static const String PRODUCT_INCLUDED_INVENTORY = "productIncludedInventory";
  static const String PRODUCT_MODEL_REFERENCE = "productModelReference";
  static const String PRODUCT_USED_IN_FORMS = "productUsedInForms";
  static const String PRODUCT_SURCHARGE = "productSurcharge";
  static const String PRODUCT_SURCHARGE_CURRENCY = "productSurchargeCurrency";
  static const String PRODUCT_DEPOSIT = "productDeposit";

  static const String PAYMENT_INFO_AMOUNT = "paymentInfoAmount";
  static const String PAYMENT_INFO_PAID = "paymentInfoPaid";
  static const String PAYMENT_INFO_ID = "paymentInfoId";
  static const String PAYMENT_INFO_RETURNED = "paymentInfoReturned";
  static const String PAYMENT_INFO_VARIABLE_SYMBOL =
      "paymentInfoVariableSymbol";
  static const String PAYMENT_INFO_DEADLINE = "orderDataDeadline";
  static const String PAYMENT_INFO_DEPOSIT_DEADLINE =
      "paymentInfoDepositDeadline";
  static const String PAYMENT_INFO_REMINDER_SENT = "isReminderSent";

  static const String ORDER_SYMBOL = "orderSymbol";
  static const String ORDER_DATA = "orderData";
  static const String ORDER_EMAIL = "orderEmail";
  static const String ORDER_CREATED_AT = "orderCreatedAt";
  static const String ORDER_DATA_NOTE = "orderDataNote";
  static const String ORDER_NOTE_HIDDEN = "orderDataNoteHidden";
  static const String ORDER_HISTORY = "orderHistory";
  static const String ORDER_TRANSACTIONS = "orderTransactions";

  static const String ORDER_FORM = "orderForm";
  static const String ORDER_CONTRACT_DOWNLOAD = "orderContractDownload";

  static const String RESPONSES = "responses";

  static const String HISTORY_ID = "historyId";
  static const String HISTORY_ORDER_SYMBOL = "historyOrderSymbol";
  static const String HISTORY_CHANGED_AT = "historyChangedAt";
  static const String HISTORY_CHANGED_BY = "historyChangedBy";
  static const String HISTORY_STATE = "historyState";
  static const String HISTORY_PRICE = "historyPrice";
  static const String HISTORY_CHANGES_SUMMARY = "historyChangesSummary";
  static const String HISTORY_MODEL_REFERENCE = "historyModelReference";

  // Define columns
  static Map<String, dynamic> columnBuilders(BuildContext context) => {
        PRODUCT_ID: [
          TrinaColumn(
            hide: true,
            readOnly: true,
            enableEditingMode: false,
            title: OrdersStrings.gridId,
            field: PRODUCT_ID,
            type: TrinaColumnType.number(defaultValue: -1),
            width: 50,
            renderer: (r) => DataGridHelper.idRenderer(r),
          ),
        ],
        // ... [Other columns omitted for brevity, keeping structure] ...
        PRODUCT_IS_HIDDEN: [
          TrinaColumn(
            title: OrdersStrings.gridHide,
            field: PRODUCT_IS_HIDDEN,
            type: TrinaColumnType.text(),
            applyFormatterInEditing: true,
            enableEditingMode: false,
            width: 100,
            renderer: (ctx) =>
                DataGridHelper.checkBoxRenderer(ctx, PRODUCT_IS_HIDDEN),
          ),
        ],
        PRODUCT_TITLE: [
          TrinaColumn(
            enableAutoEditing: true,
            title: OrdersStrings.gridTitle,
            field: PRODUCT_TITLE,
            type: TrinaColumnType.text(),
            width: 200,
          ),
        ],
        PRODUCT_SHORT_TITLE: [
          TrinaColumn(
            enableAutoEditing: true,
            title: OrdersStrings.gridShortTitle,
            field: PRODUCT_SHORT_TITLE,
            type: TrinaColumnType.text(),
            width: 150,
          ),
        ],
        PRODUCT_PRICE: [
          TrinaColumn(
            enableAutoEditing: true,
            title: OrdersStrings.gridPrice,
            field: PRODUCT_PRICE,
            type: TrinaColumnType.number(
                negative: false,
                format: "#.##",
                locale: context.locale.languageCode),
            textAlign: TrinaColumnTextAlign.end,
            width: 80,
          ),
        ],
        PRODUCT_TYPE: [
          TrinaColumn(
            readOnly: true,
            enableEditingMode: true,
            title: OrdersStrings.gridProductType,
            field: PRODUCT_TYPE,
            type: TrinaColumnType.text(),
            width: 250,
          ),
        ],
        PRODUCT_ORDER: [
          TrinaColumn(
            enableAutoEditing: true,
            title: OrdersStrings.gridOrder,
            field: PRODUCT_ORDER,
            type: TrinaColumnType.number(defaultValue: 0),
            textAlign: TrinaColumnTextAlign.end,
            width: 80,
          ),
        ],
        PRODUCT_MAXIMUM: [
          TrinaColumn(
            enableAutoEditing: true,
            title: OrdersStrings.gridMax,
            field: PRODUCT_MAXIMUM,
            formatter: (s) => s == 0 ? "" : s.toString(),
            applyFormatterInEditing: true,
            type: TrinaColumnType.number(defaultValue: 0, negative: false),
            textAlign: TrinaColumnTextAlign.end,
            width: 80,
          ),
        ],
        PRODUCT_ORDERED_COUNT: [
          TrinaColumn(
            readOnly: true,
            enableEditingMode: true,
            title: OrdersStrings.gridOrdered,
            field: PRODUCT_ORDERED_COUNT,
            type: TrinaColumnType.number(defaultValue: 0),
            textAlign: TrinaColumnTextAlign.end,
            width: 100,
          ),
        ],
        PRODUCT_PAID_COUNT: [
          TrinaColumn(
            readOnly: true,
            enableEditingMode: true,
            title: OrdersStrings.gridPaid,
            field: PRODUCT_PAID_COUNT,
            type: TrinaColumnType.number(defaultValue: 0),
            textAlign: TrinaColumnTextAlign.end,
            width: 100,
          ),
        ],
        PRODUCT_CURRENCY_CODE: [
          TrinaColumn(
            readOnly: true,
            enableEditingMode: true,
            title: OrdersStrings.gridCurrency,
            field: PRODUCT_CURRENCY_CODE,
            type: TrinaColumnType.text(),
            textAlign: TrinaColumnTextAlign.center,
            width: 80,
          ),
        ],
        PRODUCT_DEPOSIT: [
          TrinaColumn(
            enableAutoEditing: true,
            title: OrdersStrings.gridDeposit,
            field: PRODUCT_DEPOSIT,
            type: TrinaColumnType.number(
                negative: false,
                format: "#.##",
                locale: context.locale.languageCode),
            textAlign: TrinaColumnTextAlign.end,
            width: 100,
          ),
        ],
        PRODUCT_SURCHARGE: [
          TrinaColumn(
            enableAutoEditing: true,
            title: OrdersStrings.gridSurcharge,
            field: PRODUCT_SURCHARGE,
            // Negative amounts allowed (slevy) — only used in virtual mode anyway.
            type: TrinaColumnType.number(
                negative: true,
                format: "#.##",
                locale: context.locale.languageCode),
            textAlign: TrinaColumnTextAlign.end,
            width: 100,
          ),
        ],
        PRODUCT_SURCHARGE_CURRENCY: [
          TrinaColumn(
            // Free-text ISO code (3 letters). Surcharge doesn't go through the
            // bank, so it is NOT restricted to the occasion's bank-supported
            // currencies. Cell value is normalized to uppercase on save (see
            // ProductModel.fromPlutoJson).
            enableAutoEditing: true,
            title: OrdersStrings.gridCurrency,
            field: PRODUCT_SURCHARGE_CURRENCY,
            type: TrinaColumnType.text(),
            textAlign: TrinaColumnTextAlign.center,
            width: 80,
          ),
        ],
        PRODUCT_DESCRIPTION: (Map<String, dynamic> data) => [
              TrinaColumn(
                title: OrdersStrings.gridDescription,
                field: PRODUCT_DESCRIPTION,
                type: TrinaColumnType.text(),
                width: 150,
                renderer: (ctx) {
                  return DataGridHelper.buildHtmlEditorButton(
                    context: context,
                    occasionId: data[PRODUCT_DESCRIPTION],
                    field: PRODUCT_DESCRIPTION,
                    title: ctx.row.cells[PRODUCT_TITLE]!.value,
                    rendererContext: ctx,
                    loadContent: () async =>
                        ctx.row.cells[PRODUCT_DESCRIPTION]!.value,
                  );
                },
              ),
            ],
        PRODUCT_INCLUDED_INVENTORY: (Map<String, dynamic> data) => [
              TrinaColumn(
                title: InventoryStrings.included,
                field: PRODUCT_INCLUDED_INVENTORY,
                type: TrinaColumnType.text(),
                width: 350,
                enableEditingMode: false,
                renderer: (ctx) {
                  final product = ctx.row.cells[PRODUCT_MODEL_REFERENCE]?.value
                      as ProductModel?;
                  final allContexts = data[PRODUCT_INCLUDED_INVENTORY]
                      as List<InventoryContextModel>;

                  if (product == null) {
                    return const SizedBox.shrink();
                  }

                  return InventoryInclusionRenderer(
                    rendererContext: ctx,
                    product: product,
                    availableContexts: allContexts,
                  );
                },
              ),
            ],
        PRODUCT_USED_IN_FORMS: [
          TrinaColumn(
            title: OrdersStrings.gridUsedInForms,
            textAlign: TrinaColumnTextAlign.end,
            field: PRODUCT_USED_IN_FORMS,
            type: TrinaColumnType.text(),
            width: 250,
            readOnly: true,
          ),
        ],
        TICKET_ID: [
          TrinaColumn(
            hide: true,
            readOnly: true,
            enableEditingMode: false,
            title: OrdersStrings.gridId,
            field: TICKET_ID,
            type: TrinaColumnType.number(defaultValue: -1),
            width: 50,
            renderer: (rendererContext) =>
                DataGridHelper.idRenderer(rendererContext),
          ),
        ],
        TICKET_SYMBOL: [
          TrinaColumn(
            readOnly: true,
            enableEditingMode: true,
            title: OrdersStrings.itemSymbol,
            field: TICKET_SYMBOL,
            type: TrinaColumnType.text(),
            width: 120,
          ),
        ],
        TICKET_STATE: [
          TrinaColumn(
            cellPadding: EdgeInsets.zero,
            readOnly: true,
            enableEditingMode: false,
            title: OrdersStrings.gridState,
            field: TICKET_STATE,
            type: TrinaColumnType.select(
              OrderModel.statesToDataGridFormat(),
            ),
            renderer: (rendererContext) => _originalOrderStateRenderer(context,
                rendererContext, OrderModel.singleDataGridStateToColor),
            width: 140,
            textAlign: TrinaColumnTextAlign.center,
          ),
        ],
        TICKET_DOWNLOAD: (Map<String, dynamic> data) => [
              TrinaColumn(
                title: "",
                field: TICKET_DOWNLOAD,
                type: TrinaColumnType.text(),
                readOnly: true,
                enableEditingMode: false,
                width: 60,
                renderer: (rendererContext) {
                  return IconButton(
                    icon: const Icon(Icons.download),
                    tooltip: OrdersStrings
                        .downloadTicket, // Localize tooltip if preferred
                    onPressed: () async {
                      final ticketId =
                          rendererContext.row.cells[TICKET_ID]!.value as int;
                      final ticketSymbol =
                          rendererContext.row.cells[TICKET_SYMBOL]?.value ??
                              ticketId.toString();

                      // 1. Extract Customer and Spot info for the title
                      final customerName = rendererContext
                              .row.cells[ORDER_DATA]?.value
                              ?.toString() ??
                          "";
                      final spotName = rendererContext
                              .row.cells[TICKET_SPOT]?.value
                              ?.toString() ??
                          "";

                      // 2. Determine the dialog title based on available data
                      String dialogTitle = OrdersStrings.generatingPdf;
                      if (customerName.isNotEmpty && spotName.isNotEmpty) {
                        dialogTitle = OrdersStrings.generatingPdfForWithSpot(
                            customerName, spotName);
                      } else if (customerName.isNotEmpty) {
                        dialogTitle =
                            OrdersStrings.generatingPdfFor(customerName);
                      }

                      // 3. Show dialog
                      final pdfBytes = await DialogHelper
                          .showFutureProgressDialog<Uint8List?>(
                        context: context,
                        title: dialogTitle,
                        futureCallback: () =>
                            DbTickets.downloadTicketPdf(ticketId),
                      );

                      if (pdfBytes != null) {
                        await FileSaver.instance.saveFile(
                          name: "ticket_$ticketSymbol",
                          bytes: pdfBytes,
                          mimeType: MimeType.pdf,
                        );
                      } else {
                        // Error handled in DialogHelper/DbTickets
                      }
                    },
                  );
                },
              ),
            ],
        TICKET_TOTAL_PRICE: [
          TrinaColumn(
            readOnly: true,
            enableEditingMode: true,
            title: OrdersStrings.gridPrice,
            field: TICKET_TOTAL_PRICE,
            type: TrinaColumnType.text(),
            textAlign: TrinaColumnTextAlign.end,
            width: 100,
          ),
        ],
        TICKET_CREATED_AT: [
          TrinaColumn(
            readOnly: true,
            enableEditingMode: false,
            title: OrdersStrings.gridCreated,
            field: TICKET_CREATED_AT,
            type: TrinaColumnType.text(),
            textAlign: TrinaColumnTextAlign.end,
            width: 100,
          ),
        ],
        TICKET_LAST_CHANGE: [
          TrinaColumn(
            readOnly: true,
            enableEditingMode: false,
            title: OrdersStrings.gridChangedAt,
            field: TICKET_LAST_CHANGE,
            type: TrinaColumnType.text(),
            textAlign: TrinaColumnTextAlign.end,
            width: 140,
          ),
        ],
        TICKET_PRODUCTS: [
          TrinaColumn(
            readOnly: true,
            enableEditingMode: true,
            title: OrdersStrings.gridProducts,
            field: TICKET_PRODUCTS,
            type: TrinaColumnType.text(),
            width: 300,
          ),
        ],
        TICKET_NOTE: [
          TrinaColumn(
            readOnly: true,
            enableEditingMode: true,
            title: OrdersStrings.gridNote,
            field: TICKET_NOTE,
            type: TrinaColumnType.text(),
            width: 200,
          ),
        ],
        TICKET_NOTE_HIDDEN: [
          TrinaColumn(
            enableAutoEditing: true,
            title: OrdersStrings.gridHiddenNote,
            field: TICKET_NOTE_HIDDEN,
            type: TrinaColumnType.text(),
            width: 200,
          ),
        ],
        TICKET_SPOT: [
          TrinaColumn(
            readOnly: true,
            enableEditingMode: true,
            title: OrdersStrings.gridSpot,
            field: TICKET_SPOT,
            type: TrinaColumnType.text(),
            width: 60,
          ),
        ],
        ORDER_ID: [
          TrinaColumn(
            hide: true,
            title: OrdersStrings.gridId,
            field: ORDER_ID,
            type: TrinaColumnType.number(defaultValue: -1),
            readOnly: true,
            enableEditingMode: false,
            width: 50,
            renderer: (rendererContext) =>
                DataGridHelper.idRenderer(rendererContext),
          ),
        ],
        ORDER_SYMBOL: [
          TrinaColumn(
            readOnly: true,
            enableEditingMode: true,
            title: OrdersStrings.gridOrderSymbol,
            field: ORDER_SYMBOL,
            type: TrinaColumnType.text(),
            width: 120,
          ),
        ],
        ORDER_PRICE: [
          TrinaColumn(
            readOnly: true,
            enableEditingMode: true,
            title: OrdersStrings.gridPrice,
            field: ORDER_PRICE,
            type: TrinaColumnType.text(),
            textAlign: TrinaColumnTextAlign.end,
            width: FeatureService.isFeatureEnabled(FeatureConstants.deposit)
                ? 140
                : 100,
            renderer: FeatureService.isFeatureEnabled(FeatureConstants.deposit)
                ? (ctx) {
                    final order = ctx.row.cells[ORDER_MODEL_REFERENCE]?.value
                        as OrderModel?;
                    if (order == null) return const SizedBox.shrink();
                    return OrderPriceDepositRenderer(
                      rendererContext: ctx,
                      order: order,
                    );
                  }
                : null,
          ),
        ],
        ORDER_STATE: [
          TrinaColumn(
            cellPadding: EdgeInsets.zero,
            readOnly: true,
            enableEditingMode: false,
            title: OrdersStrings.gridState,
            field: ORDER_STATE,
            type: TrinaColumnType.select(
              OrderModel.statesToDataGridFormat(),
            ),
            renderer: (rendererContext) => _originalOrderStateRenderer(context,
                rendererContext, OrderModel.singleDataGridStateToColor),
            textAlign: TrinaColumnTextAlign.center,
            width: 140,
          ),
        ],
        ORDER_DATA: [
          TrinaColumn(
            readOnly: true,
            enableEditingMode: true,
            title: OrdersStrings.gridCustomer,
            field: ORDER_DATA,
            type: TrinaColumnType.text(),
            width: 150,
          ),
        ],
        ORDER_EMAIL: [
          TrinaColumn(
            readOnly: true,
            enableEditingMode: true,
            title: OrdersStrings.gridEmail,
            field: ORDER_EMAIL,
            type: TrinaColumnType.text(),
            width: 140,
          ),
        ],
        ORDER_CREATED_AT: [
          TrinaColumn(
            readOnly: true,
            enableEditingMode: false,
            title: OrdersStrings.gridCreated,
            field: ORDER_CREATED_AT,
            type: TrinaColumnType.text(),
            textAlign: TrinaColumnTextAlign.end,
            width: 100,
          ),
        ],
        ORDER_DATA_NOTE: [
          TrinaColumn(
            readOnly: true,
            enableEditingMode: true,
            title: OrdersStrings.gridNote,
            field: ORDER_DATA_NOTE,
            type: TrinaColumnType.text(),
            width: 200,
          ),
        ],
        ORDER_NOTE_HIDDEN: [
          TrinaColumn(
            enableAutoEditing: true,
            title: OrdersStrings.gridHiddenNote,
            field: ORDER_NOTE_HIDDEN,
            type: TrinaColumnType.text(),
            width: 200,
          ),
        ],
        ORDER_HISTORY: [
          TrinaColumn(
            enableAutoEditing: false,
            title: OrdersStrings.gridHistory,
            field: ORDER_HISTORY,
            type: TrinaColumnType.text(),
            width: 150,
            renderer: (rendererContext) {
              return ElevatedButton(
                onPressed: () async {
                  var id = rendererContext.row.cells[ORDER_ID]!.value;
                  await _showOrderHistory(context, id);
                },
                child: Row(
                  children: [
                    const Icon(Icons.history),
                    Padding(
                      padding: const EdgeInsets.all(6),
                      child: Text(OrdersStrings.gridHistory),
                    ),
                  ],
                ),
              );
            },
          ),
        ],
        ORDER_CONTRACT_DOWNLOAD: (Map<String, dynamic> data) => [
              TrinaColumn(
                title: "",
                field: ORDER_CONTRACT_DOWNLOAD,
                type: TrinaColumnType.text(),
                readOnly: true,
                enableEditingMode: false,
                width: 60,
                renderer: (rendererContext) {
                  return IconButton(
                    icon: const Icon(Icons.download),
                    tooltip: FeaturesStrings.downloadContract,
                    onPressed: () async {
                      final orderId =
                          rendererContext.row.cells[ORDER_ID]!.value as int;
                      final orderSymbol =
                          rendererContext.row.cells[ORDER_SYMBOL]?.value ??
                              orderId.toString();

                      final customerName = rendererContext
                              .row.cells[ORDER_DATA]?.value
                              ?.toString() ??
                          "";

                      String dialogTitle = FeaturesStrings.generatingContract;
                      if (customerName.isNotEmpty) {
                        dialogTitle =
                            FeaturesStrings.generatingContractFor(customerName);
                      }

                      final pdfBytes = await DialogHelper
                          .showFutureProgressDialog<Uint8List?>(
                        context: context,
                        title: dialogTitle,
                        futureCallback: () =>
                            DbOrders.downloadContractPdf(orderId),
                      );

                      if (pdfBytes != null) {
                        await FileSaver.instance.saveFile(
                          name: "contract_$orderSymbol",
                          bytes: pdfBytes,
                          mimeType: MimeType.pdf,
                        );
                      }
                    },
                  );
                },
              ),
            ],
        ORDER_TRANSACTIONS: (Map<String, dynamic> data) => [
              TrinaColumn(
                enableAutoEditing: false,
                title: OrdersStrings.gridTransactions,
                field: ORDER_TRANSACTIONS,
                type: TrinaColumnType.text(),
                width: 150,
                renderer: (rendererContext) {
                  return ElevatedButton(
                    onPressed: () async {
                      var id = rendererContext.row.cells[ORDER_ID]!.value;
                      var unitId = data["unitId"] as int?;
                      await _showOrderTransactions(context, id, unitId: unitId);
                      var transactionsAfterFunction = data[ORDER_TRANSACTIONS];
                      if (transactionsAfterFunction is Future<void>
                          Function()?) {
                        transactionsAfterFunction?.call();
                      }
                    },
                    child: Row(
                      children: [
                        const Icon(Icons.payment),
                        Padding(
                          padding: const EdgeInsets.all(6),
                          child: Text(OrdersStrings.gridTransactions),
                        ),
                      ],
                    ),
                  );
                },
              ),
            ],
        TICKET_PRODUCTS_EDIT: (Map<String, dynamic> data) => [
              TrinaColumn(
                enableAutoEditing: false,
                title: OrdersStrings.gridProducts,
                field: TICKET_PRODUCTS_EDIT,
                type: TrinaColumnType.text(),
                width: 150,
                renderer: (rendererContext) {
                  return ElevatedButton(
                    onPressed: () async {
                      final ticketId =
                          rendererContext.row.cells[TICKET_ID]!.value as int;
                      final changed =
                          await _showTicketProducts(context, ticketId);
                      if (changed == true) {
                        var afterFunction = data[TICKET_PRODUCTS_EDIT];
                        if (afterFunction is Future<void> Function()?) {
                          afterFunction?.call();
                        }
                      }
                    },
                    child: Row(
                      children: [
                        const Icon(Icons.category),
                        Padding(
                          padding: const EdgeInsets.all(6),
                          child: Text(OrdersStrings.gridProducts),
                        ),
                      ],
                    ),
                  );
                },
              ),
            ],
        TICKET_CONFIRM: (Map<String, dynamic> data) => [
              TrinaColumn(
                enableAutoEditing: false,
                title: OrdersStrings.ticketUsage,
                field: TICKET_CONFIRM,
                type: TrinaColumnType.text(),
                width: 200,
                renderer: (rendererContext) {
                  final formattedState =
                      rendererContext.row.cells[TICKET_STATE]?.value as String?;
                  final isUsed =
                      formattedState?.split(';').first == OrderModel.usedState;
                  final canToggleUsage = canToggleTicketUsage(formattedState);
                  final actionLabel = isUsed
                      ? OrdersStrings.restoreTicket
                      : OrdersStrings.confirmTicket;

                  return ElevatedButton(
                    onPressed: canToggleUsage
                        ? () async {
                            final ticketId = rendererContext
                                .row.cells[TICKET_ID]!.value as int;
                            final ticketSymbol = rendererContext.row
                                    .cells[TICKET_SYMBOL]?.value as String? ??
                                ticketId.toString();

                            // Using the ticket symbol directly as the confirmation message body for simplicity.
                            var confirm =
                                await DialogHelper.showConfirmationDialog(
                              context,
                              actionLabel,
                              ticketSymbol,
                            );

                            if (confirm == true) {
                              if (isUsed) {
                                await DbTickets.unuseTicket(ticketId);
                              } else {
                                await DbTickets.useTicket(ticketId);
                              }
                              if (context.mounted) {
                                ToastHelper.Show(
                                  context,
                                  "$ticketSymbol: ${CommonStrings.ok}",
                                );
                              }
                              var afterFunction = data[TICKET_CONFIRM];
                              if (afterFunction is Future<void> Function()?) {
                                afterFunction?.call();
                              }
                            }
                          }
                        : null,
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(isUsed ? Icons.undo : Icons.check),
                        Padding(
                          padding: const EdgeInsets.all(6),
                          child: Text(actionLabel),
                        ),
                      ],
                    ),
                  );
                },
              ),
            ],
        PAYMENT_INFO_AMOUNT: [
          TrinaColumn(
            readOnly: true,
            enableEditingMode: true,
            title: OrdersStrings.gridAmount,
            field: PAYMENT_INFO_AMOUNT,
            type: TrinaColumnType.text(),
            textAlign: TrinaColumnTextAlign.end,
            width: 80,
          ),
        ],
        PAYMENT_INFO_ID: [
          TrinaColumn(
            hide: true,
            readOnly: true,
            enableEditingMode: false,
            title: "Payment Info ID",
            field: PAYMENT_INFO_ID,
            type: TrinaColumnType.number(defaultValue: 0),
            width: 50,
          ),
        ],
        PAYMENT_INFO_PAID: (Map<String, dynamic> data) => [
              TrinaColumn(
                readOnly: true,
                enableEditingMode: true,
                title: OrdersStrings.gridPaid,
                field: PAYMENT_INFO_PAID,
                type: TrinaColumnType.text(),
                textAlign: TrinaColumnTextAlign.end,
                width: 150,
                renderer: (ctx) {
                  final val = ctx.cell.value?.toString() ?? "";
                  final canUpdate = RightsService.canUpdateOrders();
                  return Row(
                    children: [
                      InkWell(
                        borderRadius: BorderRadius.circular(12),
                        onTap: !canUpdate
                            ? null
                            : () async {
                                int? unitId = data["unitId"] as int?;
                                if (unitId == null) {
                                  ToastHelper.Show(
                                      context, "Unit ID not found.",
                                      severity: ToastSeverity.NotOk);
                                  return;
                                }

                                String currency = "CZK";
                                String? priceString = ctx
                                    .row.cells[EshopColumns.ORDER_PRICE]?.value
                                    ?.toString();
                                if (priceString != null &&
                                    priceString.isNotEmpty) {
                                  var parts = priceString.trim().split(" ");
                                  if (parts.length > 1) {
                                    currency = parts.last;
                                  }
                                }

                                String variableSymbol = ctx
                                        .row
                                        .cells[EshopColumns
                                            .PAYMENT_INFO_VARIABLE_SYMBOL]
                                        ?.value
                                        ?.toString() ??
                                    "";

                                int? orderId = ctx
                                    .row
                                    .cells[EshopColumns.ORDER_ID]
                                    ?.value as int?;
                                bool isBankAdmin = false;

                                if (orderId != null) {
                                  var transactionObject =
                                      await DbEshop.getTransactionsForOrder(
                                          orderId);
                                  if (transactionObject != null &&
                                      transactionObject.paymentInfo != null) {
                                    var paymentInfo =
                                        transactionObject.paymentInfo!;
                                    List<int>? accountIds =
                                        RightsService.bankAccountAdmin();

                                    if (accountIds != null &&
                                        paymentInfo.bankAccount != null) {
                                      if (accountIds
                                          .contains(paymentInfo.bankAccount)) {
                                        isBankAdmin = true;
                                      }
                                    }
                                  }
                                }

                                if (!context.mounted) return;

                                final result = await showDialog(
                                  context: context,
                                  builder: (context) {
                                    int? paymentInfoId = ctx
                                        .row
                                        .cells[EshopColumns.PAYMENT_INFO_ID]
                                        ?.value as int?;
                                    if (paymentInfoId == null ||
                                        paymentInfoId == 0) return Container();

                                    return AddCashPaymentDialog(
                                      unitId: unitId,
                                      currency: currency,
                                      variableSymbol: variableSymbol,
                                      paymentInfoId: paymentInfoId,
                                      isBankAdmin: isBankAdmin,
                                    );
                                  },
                                );

                                if (result == true) {
                                  var refresh =
                                      data[EshopColumns.PAYMENT_INFO_PAID];
                                  if (refresh is Future<void> Function()?) {
                                    refresh?.call();
                                  }
                                } else if (result == 'SWITCH_TO_CASHLESS') {
                                  int? paymentInfoId = ctx
                                      .row
                                      .cells[EshopColumns.PAYMENT_INFO_ID]
                                      ?.value as int?;
                                  if (paymentInfoId != null) {
                                    int? orderId = ctx
                                        .row
                                        .cells[EshopColumns.ORDER_ID]
                                        ?.value as int?;

                                    if (orderId != null) {
                                      var transactionObject =
                                          await DbEshop.getTransactionsForOrder(
                                              orderId);
                                      if (transactionObject != null &&
                                          transactionObject.paymentInfo !=
                                              null) {
                                        var paymentInfo =
                                            transactionObject.paymentInfo!;

                                        if (paymentInfo.bankAccount != null) {
                                          final searchResult = await showDialog(
                                            context: context,
                                            builder: (context) =>
                                                SearchTransactionsDialog(
                                              paymentInfoId: paymentInfo.id!,
                                              bankAccount:
                                                  paymentInfo.bankAccount!,
                                            ),
                                          );

                                          if (searchResult == true) {
                                            var refresh = data[
                                                EshopColumns.PAYMENT_INFO_PAID];
                                            if (refresh is Future<void>
                                                Function()?) {
                                              refresh?.call();
                                            }
                                          }
                                        } else {
                                          ToastHelper.Show(context,
                                              "No bank account linked to this order.",
                                              severity: ToastSeverity.NotOk);
                                        }
                                      } else {
                                        ToastHelper.Show(context,
                                            "Could not fetch payment info.",
                                            severity: ToastSeverity.NotOk);
                                      }
                                    } else {
                                      // Fallback: if HISTORY_ID is missing, try to find "id" or "orderId" if available in cells
                                      ToastHelper.Show(context,
                                          "Order ID not found in grid row.",
                                          severity: ToastSeverity.NotOk);
                                    }
                                  }
                                }
                              },
                        child: Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 4.0),
                          child: Icon(Icons.add_circle_outline,
                              size: 18,
                              color: canUpdate
                                  ? Colors.grey
                                  : Colors.grey.withOpacity(0.3)),
                        ),
                      ),
                      Expanded(
                        child: Text(val, textAlign: TextAlign.end),
                      ),
                    ],
                  );
                },
              ),
            ],
        PAYMENT_INFO_RETURNED: [
          TrinaColumn(
            readOnly: true,
            enableEditingMode: true,
            title: OrdersStrings.gridReturned,
            field: PAYMENT_INFO_RETURNED,
            type: TrinaColumnType.text(),
            textAlign: TrinaColumnTextAlign.end,
            width: 80,
          ),
        ],
        PAYMENT_INFO_VARIABLE_SYMBOL: [
          TrinaColumn(
            readOnly: true,
            enableEditingMode: true,
            title: OrdersStrings.gridVariableSymbol,
            field: PAYMENT_INFO_VARIABLE_SYMBOL,
            type: TrinaColumnType.text(),
            textAlign: TrinaColumnTextAlign.end,
            width: 80,
          ),
        ],
        PAYMENT_INFO_DEADLINE: [
          TrinaColumn(
            readOnly: true,
            enableEditingMode: false,
            title: FeatureService.isFeatureEnabled(FeatureConstants.deposit)
                ? OrdersStrings.gridDepositPaymentDeadline
                : OrdersStrings.gridDeadline,
            field: PAYMENT_INFO_DEADLINE,
            type: TrinaColumnType.text(),
            textAlign: TrinaColumnTextAlign.end,
            width: 100,
          ),
        ],
        if (FeatureService.isFeatureEnabled(FeatureConstants.deposit))
          PAYMENT_INFO_DEPOSIT_DEADLINE: [
            TrinaColumn(
              readOnly: true,
              enableEditingMode: false,
              title: OrdersStrings.gridDepositDeadline,
              field: PAYMENT_INFO_DEPOSIT_DEADLINE,
              type: TrinaColumnType.text(),
              textAlign: TrinaColumnTextAlign.end,
              width: 110,
            ),
          ],
        PAYMENT_INFO_REMINDER_SENT: [
          TrinaColumn(
            title: OrdersStrings.gridReminderSent,
            field: PAYMENT_INFO_REMINDER_SENT,
            type: TrinaColumnType.text(),
            enableEditingMode: false,
            width: 120,
            renderer: (rendererContext) => DataGridHelper.checkBoxRenderer(
              rendererContext,
              PAYMENT_INFO_REMINDER_SENT,
              () => false, // This makes the checkbox always read-only
            ),
          ),
        ],
        ORDER_FORM: [
          TrinaColumn(
            readOnly: true,
            enableEditingMode: true,
            title: OrdersStrings.gridForm,
            field: ORDER_FORM,
            type: TrinaColumnType.text(),
            textAlign: TrinaColumnTextAlign.start,
            width: 120,
          ),
        ],
        TICKET_PRODUCTS_EXTENDED: (Map<String, dynamic> data) {
          if (data[TICKET_PRODUCTS_EXTENDED] == null) {
            return <TrinaColumn>[];
          }
          var columns = <TrinaColumn>[];
          for (var f in (data[TICKET_PRODUCTS_EXTENDED]) as List<String>) {
            var cc = genericTextColumn(ProductModel.typeToLocale(f), f,
                alignToEnd: false);
            columns.add(cc);
          }
          return columns;
        },
        RESPONSES: (Map<String, dynamic> data) {
          if (data[RESPONSES] == null) {
            return <TrinaColumn>[];
          }
          var columns = <TrinaColumn>[];
          for (FormFieldModel f in (data[RESPONSES]) as List<FormFieldModel>) {
            var title = f.title?.trim();
            TrinaColumn cc;

            if (!FormHelper.nonEditableFields.contains(f.type)) {
              cc = genericTextColumn(
                  (title == null || title.isEmpty
                      ? FormHelper.fieldTypeToLocale(f.type!)
                      : title),
                  f.id.toString(),
                  enableEditing: true);
            } else {
              cc = genericTextColumn(
                  (title == null || title.isEmpty
                      ? FormHelper.fieldTypeToLocale(f.type!)
                      : title),
                  f.id.toString());
            }
            columns.add(cc);
          }
          return columns;
        },
        HISTORY_ID: [
          TrinaColumn(
            title: OrdersStrings.gridId,
            hide: true,
            readOnly: true,
            field: HISTORY_ID,
            type: TrinaColumnType.number(),
          ),
        ],
        HISTORY_MODEL_REFERENCE: [
          TrinaColumn(
            hide: true,
            field: HISTORY_MODEL_REFERENCE,
            type: TrinaColumnType.text(),
            title: '',
          ),
        ],
        HISTORY_ORDER_SYMBOL: [
          TrinaColumn(
            title: OrdersStrings.gridOrderSymbol,
            field: HISTORY_ORDER_SYMBOL,
            type: TrinaColumnType.text(),
            readOnly: true,
            width: 120,
          ),
        ],
        HISTORY_CHANGED_AT: [
          TrinaColumn(
            title: OrdersStrings.gridChangedAt,
            field: HISTORY_CHANGED_AT,
            type: TrinaColumnType.text(),
            readOnly: true,
            width: 140,
          ),
        ],
        HISTORY_CHANGED_BY: [
          TrinaColumn(
            title: OrdersStrings.gridChangedBy,
            field: HISTORY_CHANGED_BY,
            type: TrinaColumnType.text(),
            readOnly: true,
            width: 100,
          ),
        ],
        HISTORY_STATE: [
          TrinaColumn(
            cellPadding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
            readOnly: true,
            title: OrdersStrings.gridState,
            field: HISTORY_STATE,
            type: TrinaColumnType.text(),
            renderer: (rendererContext) => buildOrderStateRenderer(
                rendererContext.cell.value,
                OrderModel.singleDataGridStateToColor),
            textAlign: TrinaColumnTextAlign.center,
            width: 280,
          ),
        ],
        HISTORY_PRICE: [
          TrinaColumn(
            readOnly: true,
            title: OrdersStrings.gridPrice,
            field: HISTORY_PRICE,
            type: TrinaColumnType.text(),
            textAlign: TrinaColumnTextAlign.end,
            width: 160,
          ),
        ],
        HISTORY_CHANGES_SUMMARY: [
          TrinaColumn(
            title: OrdersStrings.gridChanges,
            field: HISTORY_CHANGES_SUMMARY,
            type: TrinaColumnType.text(),
            readOnly: true,
            width: 600,
            renderer: (rendererContext) {
              final historyModel = rendererContext.row
                  .cells[HISTORY_MODEL_REFERENCE]?.value as OrderHistoryModel?;
              if (historyModel == null) return const SizedBox.shrink();
              // Use the single-line version for the grid
              return historyModel.generateSingleLineSummaryWidget(context);
            },
          ),
        ],
      };

  static Widget buildOrderStateRenderer(
      String formattedState, Color Function(String) getBackground) {
    return OrderStateDisplay(
      formattedState: formattedState,
      getBackground: getBackground,
      stateTagWidth: 100,
    );
  }

  static Widget _originalOrderStateRenderer(
      BuildContext context,
      TrinaColumnRendererContext rendererContext,
      Color Function(String) getBackground) {
    String value = rendererContext.cell.value;
    String firstPart = value.split(";")[0];
    String textValue = OrderModel.statesDataGridToUpper(value.split(";").last);

    return Container(
      color: getBackground(firstPart),
      child: Center(
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              textValue,
            ),
            if (firstPart == OrderModel.expiredState)
              Padding(
                padding: const EdgeInsets.only(left: 8.0),
                child: Tooltip(
                  message: OrdersStrings.expiredOrderTooltip,
                  child: CircleAvatar(
                    radius: 12,
                    backgroundColor: ThemeConfig.redColor(context),
                    child: const Icon(
                      Icons.error_outline,
                      size: 16,
                      color: Colors.white,
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  static TrinaColumn genericTextColumn(String title, String field,
      {bool alignToEnd = true, bool enableEditing = false}) {
    return TrinaColumn(
      readOnly: !enableEditing,
      enableEditingMode: true,
      title: title,
      field: field,
      type: TrinaColumnType.text(),
      textAlign:
          alignToEnd ? TrinaColumnTextAlign.end : TrinaColumnTextAlign.start,
      width: 150,
    );
  }

  /// Generates columns based on a list of column identifiers.
  /// Optional `data` map is used for columns that require extra configuration.
  static List<TrinaColumn> generateColumns(
      BuildContext context, List<String> identifiers,
      {Map<String, dynamic>? data}) {
    var columns = columnBuilders(context);
    return identifiers.where((id) => columns.containsKey(id)).expand((id) {
      var columnEntry = columns[id];
      if (columnEntry is List<TrinaColumn>) {
        return columnEntry; // Static columns
      } else if (columnEntry is Function) {
        return (columnEntry(data ?? {}) as List<TrinaColumn>);
      }
      return <TrinaColumn>[];
    }).toList();
  }

  /// Shows the order history in a dialog.
  static Future<void> _showOrderHistory(
      BuildContext context, int orderId) async {
    await showDialog(
      context: context,
      builder: (BuildContext context) {
        return OrderHistoryDialog(orderId: orderId);
      },
    );
  }

  /// Shows the order transactions in a dialog.
  static Future<void> _showOrderTransactions(BuildContext context, int orderId,
      {int? unitId}) async {
    await showDialog(
      context: context,
      builder: (BuildContext context) {
        return TransactionsDialog(
          orderId: orderId,
          unitId: unitId,
        );
      },
    );
  }

  static const List<String> productCategories = ["others"];

  static Map<String, TrinaCell> generateProductTypeCells(
      List<ProductModel> products) {
    // Get the allowed product categories.
    final List<String> allowedCategories = productCategories;

    // Initialize a map with each allowed category mapped to an empty list.
    final Map<String, List<ProductModel>> groupedProducts = {
      for (var category in allowedCategories) category: [],
    };

    // Group products by their type.
    // If the product type is not in allowedCategories,
    // assign it to the last category in the allowed list.
    for (var product in products) {
      final String productType = product.productTypeString ?? "";
      final String categoryKey = allowedCategories.contains(productType)
          ? productType
          : allowedCategories.last;
      groupedProducts[categoryKey]!.add(product);
    }

    // Build a cell for each allowed category; if no products are present, set an empty value.
    final Map<String, TrinaCell> productCells = {};
    for (var category in allowedCategories) {
      final String cellValue = groupedProducts[category]!.isNotEmpty
          ? groupedProducts[category]!.map((p) => p.toBasicString()).join(" | ")
          : "";
      productCells[category] = TrinaCell(value: cellValue);
    }

    return productCells;
  }

  static Future<bool?> _showTicketProducts(BuildContext context, int ticketId) {
    return showDialog<bool>(
      context: context,
      builder: (_) => ProductsDialog(ticketId: ticketId),
    );
  }
}
