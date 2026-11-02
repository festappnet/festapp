import 'package:fstapp/services/locale_date_time.dart';
import 'package:auto_route/auto_route.dart';
import 'package:fstapp/app_router.dart';
import '../navigation/root_route_navigation.dart';
import 'package:fstapp/data_services/authorization_capabilities.dart';
import 'ticket_batch_strings.dart';
import 'package:fstapp/components/eshop/eshop_column_ids.dart';
import '../forms/waitlist_commands.dart';
import '../forms/order_overview_strings.dart';
import 'package:fstapp/services/exception_handler.dart';
import 'package:fstapp/services/launch_url_service.dart';
import 'package:fstapp/components/single_data_grid/data_grid_action_confirmation.dart';
import 'models/ticket_model.dart';
import '../forms/waitlist_strings.dart';
import 'views/waitlist_order_detail.dart';
import 'order_symbol_cell.dart';
import 'order_grid_filters.dart';
import 'package:fstapp/components/email_delivery/email_delivery_indicator.dart';
import 'package:fstapp/components/email_delivery/email_delivery_strings.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:file_saver/file_saver.dart'; // Added for file saving
import 'package:fstapp/components/_shared/common_strings.dart';
import 'package:flutter/foundation.dart';
import 'package:material_ui/material_ui.dart';
import 'package:fstapp/components/inventory/models/inventory_context_model.dart';
import 'package:fstapp/components/inventory/views/inventory_strings.dart';
import 'package:fstapp/components/single_data_grid/data_grid_helper.dart';
import 'package:festapp_core/forms.dart';
import 'package:fstapp/components/eshop/models/order_model.dart';
import 'package:festapp_core/eshop.dart';
import 'package:fstapp/components/eshop/product_grid_record.dart';
import 'package:fstapp/components/eshop/order_item_strings.dart';
import 'package:fstapp/components/eshop/views/products_dialog.dart';
import 'package:fstapp/components/eshop/views/transactions_dialog.dart';
import 'package:fstapp/components/forms/widgets_view/form_helper.dart';
import 'package:fstapp/components/eshop/db_tickets.dart';
import 'package:fstapp/components/eshop/db_orders.dart';
import 'package:fstapp/components/eshop/db_eshop.dart';
import 'package:fstapp/services/dialog_helper.dart';
import 'package:fstapp/services/toast_helper.dart';
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
import 'views/order_state_cell.dart';
import 'package:fstapp/components/features/features_strings.dart';
import 'package:fstapp/components/eshop/views/search_transactions_dialog.dart';
import 'views/add_cash_payment_dialog.dart';

bool canToggleTicketUsage(String? formattedState) => ![
      OrderModel.stornoState,
      OrderModel.waitlistedState
    ].contains(formattedState?.split(';').first);

bool canDownloadTicket(String? formattedState) =>
    formattedState?.split(';').first != OrderModel.waitlistedState;

class EshopColumns {
  // Column identifier constants

  // Define columns
  // These narrow identity columns use a tooltip rather than the shared
  // interactive help button, whose accessible controls require 160 px.
  static Widget _compactOrderHeader(
          TrinaColumnTitleRendererContext r, String help) =>
      Builder(
          builder: (context) => Tooltip(
                message: '${r.column.title}\n$help',
                child: Container(
                  height: r.height,
                  decoration: BoxDecoration(
                      color: r.column.backgroundColor,
                      border: BorderDirectional(
                          end: r.stateManager.style.enableColumnBorderVertical
                              ? BorderSide(
                                  color: r.stateManager.style.borderColor)
                              : BorderSide.none)),
                  padding: r.column.titlePadding ??
                      r.stateManager.style.defaultColumnTitlePadding,
                  child: Row(children: [
                    Expanded(
                        child: Text(r.column.title,
                            style: r.stateManager.style.columnTextStyle,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis)),
                    if (r.isFiltered)
                      SizedBox(
                          width: 24,
                          child: IconButton(
                            padding: EdgeInsets.zero,
                            iconSize: 18,
                            icon: const Icon(Icons.filter_alt_outlined),
                            onPressed: () => r.stateManager.showFilterPopup(
                                context,
                                calledColumn: r.column),
                          )),
                    if (r.showContextIcon)
                      SizedBox(width: 24, child: r.contextMenuIcon),
                  ]),
                ),
              ));

  static TrinaColumn orderSequenceColumn() => TrinaColumn(
        readOnly: true,
        enableEditingMode: false,
        title: OrdersStrings.gridOrderSequence,
        field: EshopColumnIds.ORDER_SEQUENCE,
        type: TrinaColumnType.number(format: "#", defaultValue: null),
        width: 76,
        titleRenderer: (r) =>
            _compactOrderHeader(r, OrdersStrings.gridOrderSequenceHelp),
      );

  static double _orderSymbolWidth(BuildContext context) {
    final painter = TextPainter(
      text: TextSpan(
          text: '9W9W9W9W9W',
          style: DefaultTextStyle.of(context)
              .style
              .merge(TrinaGridStyleConfig.defaultLightCellTextStyle)),
      textDirection: Directionality.of(context),
      textScaler: MediaQuery.textScalerOf(context),
    )..layout();
    final width =
        (painter.width + 46).ceilToDouble().clamp(144.0, double.infinity);
    painter.dispose();
    return width;
  }

  static TrinaColumn orderSymbolColumn({BuildContext? context, void Function(int)? onOpen}) => TrinaColumn(
        readOnly: true,
        enableEditingMode: true,
        title: OrdersStrings.gridOrderSymbol,
        field: EshopColumnIds.ORDER_SYMBOL,
        renderer: (r) => OrderSymbolCell(
            symbol: r.cell.value?.toString() ?? '',
            onOpen: onOpen==null ? null : ()=>onOpen(r.row.cells[EshopColumnIds.ORDER_ID]!.value as int),
            style: r.stateManager.style.cellTextStyle),
        titleRenderer: (r) =>
            _compactOrderHeader(r, OrdersStrings.gridOrderSymbol),
        type: TrinaColumnType.text(),
        width: context == null ? 144 : _orderSymbolWidth(context),
      );

  static Map<String, dynamic> columnBuilders(BuildContext context) => {
        EshopColumnIds.PRODUCT_ID: [
          TrinaColumn(
            hide: true,
            readOnly: true,
            enableEditingMode: false,
            title: OrdersStrings.gridId,
            field: EshopColumnIds.PRODUCT_ID,
            type: TrinaColumnType.number(defaultValue: -1),
            width: 50,
            renderer: (r) => DataGridHelper.idRenderer(r),
          ),
        ],
        // ... [Other columns omitted for brevity, keeping structure] ...
        EshopColumnIds.PRODUCT_IS_HIDDEN: [
          TrinaColumn(
            title: OrdersStrings.gridHide,
            field: EshopColumnIds.PRODUCT_IS_HIDDEN,
            type: TrinaColumnType.text(),
            applyFormatterInEditing: true,
            enableEditingMode: false,
            width: 100,
            renderer: (ctx) => DataGridHelper.checkBoxRenderer(
                ctx, EshopColumnIds.PRODUCT_IS_HIDDEN),
          ),
        ],
        EshopColumnIds.PRODUCT_TITLE: [
          TrinaColumn(
            enableAutoEditing: true,
            title: OrdersStrings.gridTitle,
            field: EshopColumnIds.PRODUCT_TITLE,
            type: TrinaColumnType.text(),
            width: 200,
          ),
        ],
        EshopColumnIds.PRODUCT_SHORT_TITLE: [
          TrinaColumn(
            enableAutoEditing: true,
            title: OrdersStrings.gridShortTitle,
            field: EshopColumnIds.PRODUCT_SHORT_TITLE,
            type: TrinaColumnType.text(),
            width: 150,
          ),
        ],
        EshopColumnIds.PRODUCT_PRICE: [
          TrinaColumn(
            enableAutoEditing: true,
            title: OrdersStrings.gridPrice,
            field: EshopColumnIds.PRODUCT_PRICE,
            type: TrinaColumnType.number(
                negative: false,
                format: "#,##0.##",
                locale: context.locale.languageCode),
            textAlign: TrinaColumnTextAlign.end,
            width: 80,
          ),
        ],
        EshopColumnIds.PRODUCT_TYPE: [
          TrinaColumn(
            readOnly: true,
            enableEditingMode: true,
            title: OrdersStrings.gridProductType,
            field: EshopColumnIds.PRODUCT_TYPE,
            type: TrinaColumnType.text(),
            width: 150,
          ),
        ],
        EshopColumnIds.PRODUCT_ORDER: [
          TrinaColumn(
            enableAutoEditing: true,
            title: OrdersStrings.gridOrder,
            field: EshopColumnIds.PRODUCT_ORDER,
            type: TrinaColumnType.number(defaultValue: 0),
            textAlign: TrinaColumnTextAlign.end,
            width: 80,
          ),
        ],
        EshopColumnIds.PRODUCT_MAXIMUM: [
          TrinaColumn(
            enableAutoEditing: true,
            title: OrdersStrings.gridMax,
            field: EshopColumnIds.PRODUCT_MAXIMUM,
            formatter: (s) => s == 0 ? "" : s.toString(),
            applyFormatterInEditing: true,
            type: TrinaColumnType.number(defaultValue: 0, negative: false),
            textAlign: TrinaColumnTextAlign.end,
            width: 80,
          ),
        ],
        EshopColumnIds.PRODUCT_ORDERED_COUNT: [
          TrinaColumn(
            readOnly: true,
            enableEditingMode: true,
            title: OrdersStrings.gridOrdered,
            field: EshopColumnIds.PRODUCT_ORDERED_COUNT,
            type: TrinaColumnType.number(defaultValue: 0),
            textAlign: TrinaColumnTextAlign.end,
            width: 100,
          ),
        ],
        EshopColumnIds.PRODUCT_PAID_COUNT: [
          TrinaColumn(
            readOnly: true,
            enableEditingMode: true,
            title: OrdersStrings.gridPaid,
            field: EshopColumnIds.PRODUCT_PAID_COUNT,
            type: TrinaColumnType.number(defaultValue: 0),
            textAlign: TrinaColumnTextAlign.end,
            width: 100,
          ),
        ],
        EshopColumnIds.PRODUCT_CURRENCY_CODE: [
          TrinaColumn(
            readOnly: true,
            enableEditingMode: true,
            title: OrdersStrings.gridCurrency,
            field: EshopColumnIds.PRODUCT_CURRENCY_CODE,
            type: TrinaColumnType.text(),
            textAlign: TrinaColumnTextAlign.center,
            width: 80,
          ),
        ],
        EshopColumnIds.PRODUCT_DEPOSIT: [
          TrinaColumn(
            enableAutoEditing: true,
            title: OrdersStrings.gridDeposit,
            field: EshopColumnIds.PRODUCT_DEPOSIT,
            type: TrinaColumnType.number(
                negative: false,
                format: "#,##0.##",
                locale: context.locale.languageCode),
            textAlign: TrinaColumnTextAlign.end,
            width: 100,
          ),
        ],
        EshopColumnIds.PRODUCT_SURCHARGE: [
          TrinaColumn(
            enableAutoEditing: true,
            title: OrdersStrings.gridSurcharge,
            field: EshopColumnIds.PRODUCT_SURCHARGE,
            // Negative amounts allowed (slevy) — only used in virtual mode anyway.
            type: TrinaColumnType.number(
                negative: true,
                format: "#,##0.##",
                locale: context.locale.languageCode),
            textAlign: TrinaColumnTextAlign.end,
            width: 100,
          ),
        ],
        EshopColumnIds.PRODUCT_SURCHARGE_CURRENCY: [
          TrinaColumn(
            // Free-text ISO code (3 letters). Surcharge doesn't go through the
            // bank, so it is NOT restricted to the occasion's bank-supported
            // currencies. Cell value is normalized to uppercase on save (see
            // ProductModel.fromPlutoJson).
            enableAutoEditing: true,
            title: OrdersStrings.gridCurrency,
            field: EshopColumnIds.PRODUCT_SURCHARGE_CURRENCY,
            type: TrinaColumnType.text(),
            textAlign: TrinaColumnTextAlign.center,
            width: 80,
          ),
        ],
        EshopColumnIds.PRODUCT_DESCRIPTION: (Map<String, dynamic> data) => [
              TrinaColumn(
                title: OrdersStrings.gridDescription,
                field: EshopColumnIds.PRODUCT_DESCRIPTION,
                type: TrinaColumnType.text(),
                width: 150,
                renderer: (ctx) {
                  return DataGridHelper.buildHtmlEditorButton(
                    context: context,
                    occasionId: (ctx
                            .row
                            .cells[EshopColumnIds.PRODUCT_MODEL_REFERENCE]
                            ?.value as ProductGridRecord?)
                        ?.product
                        .occasion,
                    field: EshopColumnIds.PRODUCT_DESCRIPTION,
                    title: ctx.row.cells[EshopColumnIds.PRODUCT_TITLE]!.value,
                    rendererContext: ctx,
                    loadContent: () async => ctx
                        .row.cells[EshopColumnIds.PRODUCT_DESCRIPTION]!.value,
                  );
                },
              ),
            ],
        EshopColumnIds.PRODUCT_INCLUDED_INVENTORY:
            (Map<String, dynamic> data) => [
                  TrinaColumn(
                    title: InventoryStrings.included,
                    field: EshopColumnIds.PRODUCT_INCLUDED_INVENTORY,
                    type: TrinaColumnType.text(),
                    width: 350,
                    enableEditingMode: false,
                    renderer: (ctx) {
                      final product = ctx
                          .row
                          .cells[EshopColumnIds.PRODUCT_MODEL_REFERENCE]
                          ?.value as ProductGridRecord?;
                      final allContexts =
                          data[EshopColumnIds.PRODUCT_INCLUDED_INVENTORY]
                              as List<InventoryContextModel>;

                      if (product == null) {
                        return const SizedBox.shrink();
                      }

                      return InventoryInclusionRenderer(
                        rendererContext: ctx,
                        product: product.product,
                        availableContexts: allContexts,
                      );
                    },
                  ),
                ],
        EshopColumnIds.PRODUCT_USED_IN_FORMS: [
          TrinaColumn(
            title: OrdersStrings.gridUsedInForms,
            textAlign: TrinaColumnTextAlign.end,
            field: EshopColumnIds.PRODUCT_USED_IN_FORMS,
            type: TrinaColumnType.text(),
            width: 250,
            readOnly: true,
          ),
        ],
        EshopColumnIds.TICKET_ID: [
          TrinaColumn(
            hide: true,
            readOnly: true,
            enableEditingMode: false,
            title: OrdersStrings.gridId,
            field: EshopColumnIds.TICKET_ID,
            type: TrinaColumnType.number(defaultValue: -1),
            width: 50,
            renderer: (rendererContext) =>
                DataGridHelper.idRenderer(rendererContext),
          ),
        ],
        for (final entry in {
          EshopColumnIds.TICKET_ORIGIN: 'origin',
          EshopColumnIds.TICKET_SALE_STATE: 'saleState',
        }.entries)
          entry.key: [
            TrinaColumn(
                readOnly: true,
                enableEditingMode: false,
                title: TicketBatchStrings.text(entry.value),
                field: entry.key,
                type: TrinaColumnType.text(),
                width: 150)
          ],
        EshopColumnIds.TICKET_BATCH: [
          TrinaColumn(
              readOnly: true,
              enableEditingMode: false,
              title: TicketBatchStrings.text('batch'),
              field: EshopColumnIds.TICKET_BATCH,
              type: TrinaColumnType.text(),
              width: 180,
              renderer: (r) {
                final ticket = r
                    .row
                    .cells[EshopColumnIds.TICKET_MODEL_REFERENCE]
                    ?.value as TicketModel?;
                final batch = ticket?.batch;
                if (batch == null) {
                  return const SizedBox.shrink();
                }
                return TextButton(
                    onPressed: () => pushRootPath(context.router.root,
                        '/${context.routeData.inheritedPathParams.getString(AppRouter.linkFormatted)}/reservations/orders/pregenerated/${batch['id']}'),
                    child: Text(batch['title'] as String));
              })
        ],
        EshopColumnIds.TICKET_SYMBOL: [
          TrinaColumn(
            readOnly: true,
            enableEditingMode: true,
            title: OrderItemStrings.itemSymbol,
            field: EshopColumnIds.TICKET_SYMBOL,
            type: TrinaColumnType.text(),
            width: 120,
          ),
        ],
        EshopColumnIds.TICKET_STATE: [
          TrinaColumn(
            cellPadding: EdgeInsets.zero,
            readOnly: true,
            enableEditingMode: false,
            title: OrdersStrings.gridState,
            field: EshopColumnIds.TICKET_STATE,
            type: TrinaColumnType.select(
              OrderModel.statesToDataGridFormat(),
            ),
            renderer: (rendererContext) => _originalOrderStateRenderer(context,
                rendererContext, OrderModel.singleDataGridStateToColor),
            width: 140,
            textAlign: TrinaColumnTextAlign.center,
          ),
        ],
        EshopColumnIds.TICKET_DOWNLOAD: (Map<String, dynamic> data) => [
              TrinaColumn(
                title: "",
                field: EshopColumnIds.TICKET_DOWNLOAD,
                type: TrinaColumnType.text(),
                readOnly: true,
                enableEditingMode: false,
                width: 60,
                renderer: (rendererContext) {
                  final ticket = rendererContext
                      .row
                      .cells[EshopColumnIds.TICKET_MODEL_REFERENCE]
                      ?.value as TicketModel?;
                  return IconButton(
                    icon: const Icon(Icons.download),
                    tooltip: OrdersStrings
                        .downloadTicket, // Localize tooltip if preferred
                    onPressed: ticket?.ticketSymbol?.trim().isNotEmpty !=
                                true ||
                            !canDownloadTicket(rendererContext
                                .row
                                .cells[EshopColumnIds.TICKET_STATE]
                                ?.value as String?)
                        ? null
                        : () async {
                            final ticketId = rendererContext.row
                                .cells[EshopColumnIds.TICKET_ID]!.value as int;
                            final ticketSymbol = rendererContext
                                    .row
                                    .cells[EshopColumnIds.TICKET_SYMBOL]
                                    ?.value ??
                                ticketId.toString();

                            // 1. Extract Customer and Spot info for the title
                            final customerName = rendererContext
                                    .row.cells[EshopColumnIds.ORDER_DATA]?.value
                                    ?.toString() ??
                                "";
                            final spotName = rendererContext.row
                                    .cells[EshopColumnIds.TICKET_SPOT]?.value
                                    ?.toString() ??
                                "";

                            // 2. Determine the dialog title based on available data
                            String dialogTitle = OrdersStrings.generatingPdf;
                            if (customerName.isNotEmpty &&
                                spotName.isNotEmpty) {
                              dialogTitle =
                                  OrdersStrings.generatingPdfForWithSpot(
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
        EshopColumnIds.TICKET_TOTAL_PRICE: [
          TrinaColumn(
            readOnly: true,
            enableEditingMode: true,
            title: OrdersStrings.gridPrice,
            field: EshopColumnIds.TICKET_TOTAL_PRICE,
            type: TrinaColumnType.text(),
            textAlign: TrinaColumnTextAlign.end,
            width: 100,
          ),
        ],
        EshopColumnIds.TICKET_CREATED_AT: [
          TrinaColumn(
            readOnly: true,
            enableEditingMode: false,
            title: OrdersStrings.gridCreated,
            field: EshopColumnIds.TICKET_CREATED_AT,
            formatter: (value) =>
                LocaleDateTime.dateCell(value, context.locale.toString()),
            type: TrinaColumnType.text(),
            textAlign: TrinaColumnTextAlign.end,
            width: 100,
          ),
        ],
        EshopColumnIds.TICKET_LAST_CHANGE: [
          TrinaColumn(
            readOnly: true,
            enableEditingMode: false,
            title: OrdersStrings.gridChangedAt,
            field: EshopColumnIds.TICKET_LAST_CHANGE,
            formatter: (value) =>
                LocaleDateTime.dateTimeCell(value, context.locale.toString()),
            type: TrinaColumnType.text(),
            textAlign: TrinaColumnTextAlign.end,
            width: 140,
          ),
        ],
        EshopColumnIds.TICKET_PRODUCTS: [
          TrinaColumn(
            readOnly: true,
            enableEditingMode: true,
            title: OrdersStrings.gridProducts,
            field: EshopColumnIds.TICKET_PRODUCTS,
            type: TrinaColumnType.text(),
            width: 300,
          ),
        ],
        EshopColumnIds.TICKET_NOTE: [
          TrinaColumn(
            readOnly: true,
            enableEditingMode: true,
            title: OrdersStrings.gridNote,
            field: EshopColumnIds.TICKET_NOTE,
            type: TrinaColumnType.text(),
            width: 200,
          ),
        ],
        EshopColumnIds.TICKET_NOTE_HIDDEN: [
          TrinaColumn(
            enableAutoEditing: true,
            title: OrdersStrings.gridHiddenNote,
            field: EshopColumnIds.TICKET_NOTE_HIDDEN,
            checkReadOnly: (row, _) =>
                !OrderGridFilters.ticketIsNonCancelled(row),
            type: TrinaColumnType.text(),
            width: 200,
          ),
        ],
        EshopColumnIds.TICKET_SPOT: [
          TrinaColumn(
            readOnly: true,
            enableEditingMode: true,
            title: OrdersStrings.gridSpot,
            field: EshopColumnIds.TICKET_SPOT,
            type: TrinaColumnType.text(),
            width: 60,
          ),
        ],
        EshopColumnIds.ORDER_ID: [
          TrinaColumn(
            hide: true,
            title: OrdersStrings.gridId,
            field: EshopColumnIds.ORDER_ID,
            type: TrinaColumnType.number(defaultValue: -1),
            readOnly: true,
            enableEditingMode: false,
            width: 50,
            renderer: (rendererContext) =>
                DataGridHelper.idRenderer(rendererContext),
          ),
        ],
        EshopColumnIds.ORDER_SEQUENCE: [orderSequenceColumn()],
        EshopColumnIds.ORDER_SYMBOL: (Map<String,dynamic> data) => [orderSymbolColumn(context:context,
          onOpen:data['openOrderDetail']==null?null:(id)=>(data['openOrderDetail'] as void Function(int,String))(id,'overview'))],
        EshopColumnIds.ORDER_PRICE: [
          TrinaColumn(
            readOnly: true,
            enableEditingMode: true,
            title: OrdersStrings.gridPrice,
            field: EshopColumnIds.ORDER_PRICE,
            type: TrinaColumnType.text(),
            textAlign: TrinaColumnTextAlign.end,
            width: FeatureService.isFeatureEnabled(FeatureConstants.deposit)
                ? 140
                : 100,
            renderer: FeatureService.isFeatureEnabled(FeatureConstants.deposit)
                ? (ctx) {
                    final order = ctx
                        .row
                        .cells[EshopColumnIds.ORDER_MODEL_REFERENCE]
                        ?.value as OrderModel?;
                    if (order == null) return const SizedBox.shrink();
                    return OrderPriceDepositRenderer(
                      rendererContext: ctx,
                      order: order,
                    );
                  }
                : null,
          ),
        ],
        EshopColumnIds.ORDER_WAITLIST: (Map<String, dynamic> data) => [
              TrinaColumn(
                  title: WaitlistStrings.detail,
                  field: EshopColumnIds.ORDER_WAITLIST,
                  type: TrinaColumnType.text(),
                  readOnly: true,
                  width: 260,
                  renderer: (ctx) {
                    final order = OrderGridFilters.order(ctx.row);
                    if (order?.waitlistSummary == null)
                      return const SizedBox.shrink();
                    return TextButton(
                        onPressed: () => showDialog(
                            context: context,
                            builder: (_) => WaitlistOrderDetail(
                                order: order,
                                onChanged: data[EshopColumnIds.ORDER_WAITLIST]
                                    as Future<void> Function()?)),
                        child: Text(order!.waitlistSummary!.label));
                  }),
            ],
        EshopColumnIds.ORDER_STATE: (Map<String, dynamic> data) => [
              TrinaColumn(
                cellPadding: EdgeInsets.zero,
                readOnly: true,
                enableEditingMode: false,
                title: OrdersStrings.gridState,
                field: EshopColumnIds.ORDER_STATE,
                type: TrinaColumnType.select(
                  OrderModel.statesToDataGridFormat(),
                ),
                renderer: (rendererContext) => _originalOrderStateRenderer(
                    context,
                    rendererContext,
                    OrderModel.singleDataGridStateToColor,
                    onChanged: data[EshopColumnIds.ORDER_STATE],
                    occasionId: data["occasionId"] as int?,
                    onOpenDetail: data["openOrderDetail"] as void Function(int, String)?,
                    label: rendererContext.cell.value
                                    .toString()
                                    .split(';')
                                    .first ==
                                OrderModel.waitlistedState &&
                            OrderGridFilters.order(rendererContext.row)
                                    ?.isWaitlisted ==
                                true
                        ? OrderGridFilters.order(rendererContext.row)
                            ?.stateLabel
                        : null),
                textAlign: TrinaColumnTextAlign.center,
                width: 140,
              ),
            ],
        EshopColumnIds.ORDER_DATA: [
          TrinaColumn(
            readOnly: true,
            enableEditingMode: true,
            title: OrdersStrings.gridCustomer,
            field: EshopColumnIds.ORDER_DATA,
            type: TrinaColumnType.text(),
            width: 150,
          ),
        ],
        EshopColumnIds.ORDER_EMAIL_DELIVERY: (Map<String, dynamic> data) => [
          TrinaColumn(
            title: EmailDeliveryStrings.title,
            field: EshopColumnIds.ORDER_EMAIL_DELIVERY,
            type: TrinaColumnType.text(),
            width: 74,
            minWidth: 64,
            readOnly: true,
            enableEditingMode: false,
            enableAutoEditing: false,
            renderer: (r) => EmailDeliveryIndicator(
              onOpen: data["openOrderDetail"] == null ? null : () =>
                  (data["openOrderDetail"] as void Function(int, String))(
                      r.row.cells[EshopColumnIds.ORDER_ID]!.value as int, 'emails'),
              summary: r.cell.value is Map
                  ? Map<String, dynamic>.from(r.cell.value as Map)
                  : null,
              orderId: r.row.cells[EshopColumnIds.ORDER_ID]?.value as int?,
              occasionId: (r.row.cells[EshopColumnIds.ORDER_MODEL_REFERENCE]
                      ?.value as OrderModel?)
                  ?.occasion,
            ),
          ),
        ],
        EshopColumnIds.ORDER_EMAIL: [
          TrinaColumn(
            readOnly: true,
            enableEditingMode: true,
            title: OrdersStrings.gridEmail,
            field: EshopColumnIds.ORDER_EMAIL,
            type: TrinaColumnType.text(),
            width: 140,
          ),
        ],
        EshopColumnIds.ORDER_CREATED_AT: [
          TrinaColumn(
            readOnly: true,
            enableEditingMode: false,
            title: OrdersStrings.gridCreated,
            field: EshopColumnIds.ORDER_CREATED_AT,
            formatter: (value) =>
                LocaleDateTime.dateCell(value, context.locale.toString()),
            type: TrinaColumnType.text(),
            textAlign: TrinaColumnTextAlign.end,
            width: 100,
          ),
        ],
        EshopColumnIds.ORDER_DATA_NOTE: [
          TrinaColumn(
            readOnly: true,
            enableEditingMode: true,
            title: OrdersStrings.gridNote,
            field: EshopColumnIds.ORDER_DATA_NOTE,
            type: TrinaColumnType.text(),
            width: 200,
          ),
        ],
        EshopColumnIds.ORDER_NOTE_HIDDEN: [
          TrinaColumn(
            enableAutoEditing: true,
            title: OrdersStrings.gridHiddenNote,
            field: EshopColumnIds.ORDER_NOTE_HIDDEN,
            checkReadOnly: (row, _) =>
                !OrderGridFilters.orderIsNonCancelled(row),
            type: TrinaColumnType.text(),
            width: 200,
          ),
        ],
        EshopColumnIds.ORDER_OVERVIEW: [
          TrinaColumn(
            title: OrderOverviewStrings.text('gridOverview'),
            field: EshopColumnIds.ORDER_OVERVIEW,
            type: TrinaColumnType.text(),
            width: 90,
            readOnly: true,
            enableEditingMode: false,
            enableSorting: false,
            renderer: (rendererContext) => IconButton(
              tooltip: OrderOverviewStrings.text('title'),
              icon: const Icon(Icons.open_in_new),
              onPressed: () => ExceptionHandler.guard(context,
                  defaultErrorMessage: OrderOverviewStrings.text('failed'),
                  futureFunction: () async {
                final id = rendererContext
                    .row.cells[EshopColumnIds.ORDER_ID]!.value as int;
                await LaunchUrlService.openExternalUrlFrom(
                    () => WaitlistCommands().adminOverviewUrl(id));
              }),
            ),
          ),
        ],
        EshopColumnIds.ORDER_HISTORY: [
          TrinaColumn(
            enableAutoEditing: false,
            title: OrdersStrings.gridHistory,
            field: EshopColumnIds.ORDER_HISTORY,
            type: TrinaColumnType.text(),
            width: 150,
            renderer: (rendererContext) {
              return ElevatedButton(
                onPressed: () async {
                  var id =
                      rendererContext.row.cells[EshopColumnIds.ORDER_ID]!.value;
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
        EshopColumnIds.ORDER_CONTRACT_DOWNLOAD: (Map<String, dynamic> data) => [
              TrinaColumn(
                title: "",
                field: EshopColumnIds.ORDER_CONTRACT_DOWNLOAD,
                type: TrinaColumnType.text(),
                readOnly: true,
                enableEditingMode: false,
                width: 60,
                renderer: (rendererContext) {
                  return IconButton(
                    icon: const Icon(Icons.download),
                    tooltip: FeaturesStrings.downloadContract,
                    onPressed: () async {
                      final orderId = rendererContext
                          .row.cells[EshopColumnIds.ORDER_ID]!.value as int;
                      final orderSymbol = rendererContext
                              .row.cells[EshopColumnIds.ORDER_SYMBOL]?.value ??
                          "";

                      final customerName = rendererContext
                              .row.cells[EshopColumnIds.ORDER_DATA]?.value
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
        EshopColumnIds.ORDER_TRANSACTIONS: (Map<String, dynamic> data) => [
              TrinaColumn(
                enableAutoEditing: false,
                title: OrdersStrings.gridTransactions,
                field: EshopColumnIds.ORDER_TRANSACTIONS,
                type: TrinaColumnType.text(),
                width: 150,
                renderer: (rendererContext) {
                  return ElevatedButton(
                    onPressed: () async {
                      var id = rendererContext
                          .row.cells[EshopColumnIds.ORDER_ID]!.value;
                      var unitId = data["unitId"] as int?;
                      await _showOrderTransactions(context, id,
                          unitId: unitId,
                          orderSymbol: rendererContext
                              .row.cells[EshopColumnIds.ORDER_SYMBOL]?.value
                              ?.toString());
                      var transactionsAfterFunction =
                          data[EshopColumnIds.ORDER_TRANSACTIONS];
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
        EshopColumnIds.TICKET_PRODUCTS_EDIT: (Map<String, dynamic> data) => [
              TrinaColumn(
                enableAutoEditing: false,
                title: OrdersStrings.gridProducts,
                field: EshopColumnIds.TICKET_PRODUCTS_EDIT,
                type: TrinaColumnType.text(),
                width: 150,
                renderer: (rendererContext) {
                  return ElevatedButton(
                    onPressed: (((rendererContext
                                        .row
                                        .cells[EshopColumnIds
                                            .TICKET_MODEL_REFERENCE]
                                        ?.value as TicketModel?)
                                    ?.allowedActions
                                    ?.contains('products') ??
                                true) &&
                            OrderGridFilters.ticketIsNonCancelled(
                                rendererContext.row))
                        ? () async {
                            final ticketId = rendererContext.row
                                .cells[EshopColumnIds.TICKET_ID]!.value as int;
                            final changed =
                                await _showTicketProducts(context, ticketId);
                            if (changed == true) {
                              var afterFunction =
                                  data[EshopColumnIds.TICKET_PRODUCTS_EDIT];
                              if (afterFunction is Future<void> Function()?) {
                                afterFunction?.call();
                              }
                            }
                          }
                        : null,
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
        EshopColumnIds.TICKET_CONFIRM: (Map<String, dynamic> data) => [
              TrinaColumn(
                enableAutoEditing: false,
                title: OrdersStrings.ticketUsage,
                field: EshopColumnIds.TICKET_CONFIRM,
                type: TrinaColumnType.text(),
                width: 200,
                renderer: (rendererContext) {
                  final formattedState = rendererContext
                      .row.cells[EshopColumnIds.TICKET_STATE]?.value as String?;
                  final isUsed =
                      formattedState?.split(';').first == OrderModel.usedState;
                  final canToggleUsage = ((rendererContext
                                  .row
                                  .cells[EshopColumnIds.TICKET_MODEL_REFERENCE]
                                  ?.value as TicketModel?)
                              ?.allowedActions
                              ?.contains(isUsed ? 'reset' : 'use') ??
                          true) &&
                      canToggleTicketUsage(formattedState) &&
                      OrderGridFilters.ticketIsNonCancelled(
                          rendererContext.row);
                  final actionLabel = isUsed
                      ? OrdersStrings.restoreTicket
                      : OrdersStrings.confirmTicket;

                  return ElevatedButton(
                    onPressed: canToggleUsage
                        ? () async {
                            final ticketId = rendererContext.row
                                .cells[EshopColumnIds.TICKET_ID]!.value as int;
                            final ticketSymbol = rendererContext
                                    .row
                                    .cells[EshopColumnIds.TICKET_SYMBOL]
                                    ?.value as String? ??
                                ticketId.toString();

                            var confirm = await DataGridActionConfirmation.show<
                                TicketModel>(
                              context: context,
                              title: actionLabel,
                              confirmButtonText: actionLabel,
                              itemsLabel: OrderItemStrings.itemsPlural,
                              items: [
                                TicketModel.fromPlutoJson(
                                    rendererContext.row.toJson())
                              ],
                              groupBy: (ticket) => ticket.relatedOrder,
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
                              var afterFunction =
                                  data[EshopColumnIds.TICKET_CONFIRM];
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
        EshopColumnIds.PAYMENT_INFO_AMOUNT: [
          TrinaColumn(
            readOnly: true,
            enableEditingMode: true,
            title: OrdersStrings.gridAmount,
            field: EshopColumnIds.PAYMENT_INFO_AMOUNT,
            type: TrinaColumnType.text(),
            textAlign: TrinaColumnTextAlign.end,
            width: 80,
          ),
        ],
        EshopColumnIds.PAYMENT_INFO_ID: [
          TrinaColumn(
            hide: true,
            readOnly: true,
            enableEditingMode: false,
            title: "Payment Info ID",
            field: EshopColumnIds.PAYMENT_INFO_ID,
            type: TrinaColumnType.number(defaultValue: 0),
            width: 50,
          ),
        ],
        EshopColumnIds.PAYMENT_INFO_PAID: (Map<String, dynamic> data) => [
              TrinaColumn(
                readOnly: true,
                enableEditingMode: true,
                title: OrdersStrings.gridPaid,
                field: EshopColumnIds.PAYMENT_INFO_PAID,
                type: TrinaColumnType.text(),
                textAlign: TrinaColumnTextAlign.end,
                width: 150,
                renderer: (ctx) {
                  final val = ctx.cell.value?.toString() ?? "";
                  final canUpdate = RightsService.canUpdateOrders() &&
                      OrderGridFilters.orderCanReceivePayment(ctx.row);
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
                                String? priceString = ctx.row
                                    .cells[EshopColumnIds.ORDER_PRICE]?.value
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
                                        .cells[EshopColumnIds
                                            .PAYMENT_INFO_VARIABLE_SYMBOL]
                                        ?.value
                                        ?.toString() ??
                                    "";

                                int? orderId = ctx
                                    .row
                                    .cells[EshopColumnIds.ORDER_ID]
                                    ?.value as int?;
                                bool canManageBankTransactions = false;

                                if (orderId != null) {
                                  var transactionObject =
                                      await DbEshop.getTransactionsForOrder(
                                          orderId);
                                  if (transactionObject != null &&
                                      transactionObject.paymentInfo != null) {
                                    var paymentInfo =
                                        transactionObject.paymentInfo!;
                                    canManageBankTransactions =
                                        RightsService.hasBankCapability(
                                      paymentInfo.bankAccount,
                                      AuthorizationCapabilities
                                          .bankTransactionsManage,
                                    );
                                  }
                                }

                                if (!context.mounted) return;

                                final result = await showDialog(
                                  context: context,
                                  builder: (context) {
                                    int? paymentInfoId = ctx
                                        .row
                                        .cells[EshopColumnIds.PAYMENT_INFO_ID]
                                        ?.value as int?;
                                    if (paymentInfoId == null ||
                                        paymentInfoId == 0) return Container();

                                    return AddCashPaymentDialog(
                                      unitId: unitId,
                                      currency: currency,
                                      variableSymbol: variableSymbol,
                                      paymentInfoId: paymentInfoId,
                                      canManageBankTransactions:
                                          canManageBankTransactions,
                                    );
                                  },
                                );

                                if (result == true) {
                                  var refresh =
                                      data[EshopColumnIds.PAYMENT_INFO_PAID];
                                  if (refresh is Future<void> Function()?) {
                                    refresh?.call();
                                  }
                                } else if (result == 'SWITCH_TO_CASHLESS') {
                                  int? paymentInfoId = ctx
                                      .row
                                      .cells[EshopColumnIds.PAYMENT_INFO_ID]
                                      ?.value as int?;
                                  if (paymentInfoId != null) {
                                    int? orderId = ctx
                                        .row
                                        .cells[EshopColumnIds.ORDER_ID]
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
                                            var refresh = data[EshopColumnIds
                                                .PAYMENT_INFO_PAID];
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
                                      // Fallback: if EshopColumnIds.HISTORY_ID is missing, try to find "id" or "orderId" if available in cells
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
        EshopColumnIds.PAYMENT_INFO_RETURNED: [
          TrinaColumn(
            readOnly: true,
            enableEditingMode: true,
            title: OrdersStrings.gridReturned,
            field: EshopColumnIds.PAYMENT_INFO_RETURNED,
            type: TrinaColumnType.text(),
            textAlign: TrinaColumnTextAlign.end,
            width: 80,
          ),
        ],
        EshopColumnIds.PAYMENT_INFO_VARIABLE_SYMBOL: [
          TrinaColumn(
            readOnly: true,
            enableEditingMode: true,
            title: OrdersStrings.gridVariableSymbol,
            field: EshopColumnIds.PAYMENT_INFO_VARIABLE_SYMBOL,
            type: TrinaColumnType.text(),
            textAlign: TrinaColumnTextAlign.end,
            width: 80,
          ),
        ],
        EshopColumnIds.PAYMENT_INFO_DEADLINE: [
          TrinaColumn(
            readOnly: true,
            enableEditingMode: false,
            title: FeatureService.isFeatureEnabled(FeatureConstants.deposit)
                ? OrdersStrings.gridDepositPaymentDeadline
                : OrdersStrings.gridDeadline,
            field: EshopColumnIds.PAYMENT_INFO_DEADLINE,
            formatter: (value) =>
                LocaleDateTime.dateCell(value, context.locale.toString()),
            type: TrinaColumnType.text(),
            textAlign: TrinaColumnTextAlign.end,
            width: 100,
          ),
        ],
        if (FeatureService.isFeatureEnabled(FeatureConstants.deposit))
          EshopColumnIds.PAYMENT_INFO_DEPOSIT_DEADLINE: [
            TrinaColumn(
              readOnly: true,
              enableEditingMode: false,
              title: OrdersStrings.gridDepositDeadline,
              field: EshopColumnIds.PAYMENT_INFO_DEPOSIT_DEADLINE,
              formatter: (value) =>
                  LocaleDateTime.dateCell(value, context.locale.toString()),
              type: TrinaColumnType.text(),
              textAlign: TrinaColumnTextAlign.end,
              width: 110,
            ),
          ],
        EshopColumnIds.PAYMENT_INFO_REMINDER_SENT: [
          TrinaColumn(
            title: OrdersStrings.gridReminderSent,
            field: EshopColumnIds.PAYMENT_INFO_REMINDER_SENT,
            type: TrinaColumnType.text(),
            enableEditingMode: false,
            width: 120,
            renderer: (rendererContext) => DataGridHelper.checkBoxRenderer(
              rendererContext,
              EshopColumnIds.PAYMENT_INFO_REMINDER_SENT,
              () => false, // This makes the checkbox always read-only
            ),
          ),
        ],
        EshopColumnIds.ORDER_FORM: [
          TrinaColumn(
            readOnly: true,
            enableEditingMode: true,
            title: OrdersStrings.gridForm,
            field: EshopColumnIds.ORDER_FORM,
            type: TrinaColumnType.text(),
            textAlign: TrinaColumnTextAlign.start,
            width: 120,
          ),
        ],
        EshopColumnIds.TICKET_PRODUCTS_EXTENDED: (Map<String, dynamic> data) {
          if (data[EshopColumnIds.TICKET_PRODUCTS_EXTENDED] == null) {
            return <TrinaColumn>[];
          }
          var columns = <TrinaColumn>[];
          for (var f in (data[EshopColumnIds.TICKET_PRODUCTS_EXTENDED])
              as List<String>) {
            var cc = genericTextColumn(ProductPresentation.typeToLocale(f), f,
                alignToEnd: false);
            columns.add(cc);
          }
          return columns;
        },
        EshopColumnIds.RESPONSES: (Map<String, dynamic> data) {
          if (data[EshopColumnIds.RESPONSES] == null) {
            return <TrinaColumn>[];
          }
          var columns = <TrinaColumn>[];
          for (FormFieldDefinition f in (data[EshopColumnIds.RESPONSES])
              as List<FormFieldDefinition>) {
            var title = f.title?.trim();
            TrinaColumn cc;

            if (!FormMetadata.nonEditableFields.contains(f.type)) {
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
        EshopColumnIds.HISTORY_ID: [
          TrinaColumn(
            title: OrdersStrings.gridId,
            hide: true,
            readOnly: true,
            field: EshopColumnIds.HISTORY_ID,
            type: TrinaColumnType.number(),
          ),
        ],
        EshopColumnIds.HISTORY_MODEL_REFERENCE: [
          TrinaColumn(
            hide: true,
            field: EshopColumnIds.HISTORY_MODEL_REFERENCE,
            type: TrinaColumnType.text(),
            title: '',
          ),
        ],
        EshopColumnIds.HISTORY_ORDER_SYMBOL: [
          TrinaColumn(
            title: OrdersStrings.gridOrderSymbol,
            field: EshopColumnIds.HISTORY_ORDER_SYMBOL,
            renderer: (r) => OrderSymbolCell(
                symbol: r.cell.value?.toString() ?? '',
                style: r.stateManager.style.cellTextStyle),
            type: TrinaColumnType.text(),
            readOnly: true,
            width: _orderSymbolWidth(context),
          ),
        ],
        EshopColumnIds.HISTORY_CHANGED_AT: [
          TrinaColumn(
            title: OrdersStrings.gridChangedAt,
            field: EshopColumnIds.HISTORY_CHANGED_AT,
            formatter: (value) =>
                LocaleDateTime.dateTimeCell(value, context.locale.toString()),
            type: TrinaColumnType.text(),
            readOnly: true,
            width: 140,
          ),
        ],
        EshopColumnIds.HISTORY_CHANGED_BY: [
          TrinaColumn(
            title: OrdersStrings.gridChangedBy,
            field: EshopColumnIds.HISTORY_CHANGED_BY,
            type: TrinaColumnType.text(),
            readOnly: true,
            width: 100,
          ),
        ],
        EshopColumnIds.HISTORY_STATE: [
          TrinaColumn(
            cellPadding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
            readOnly: true,
            title: OrdersStrings.gridState,
            field: EshopColumnIds.HISTORY_STATE,
            type: TrinaColumnType.text(),
            renderer: (rendererContext) => buildOrderStateRenderer(
                rendererContext.cell.value,
                OrderStateDisplay.historyBackground),
            textAlign: TrinaColumnTextAlign.center,
            width: 280,
          ),
        ],
        EshopColumnIds.HISTORY_PRICE: [
          TrinaColumn(
            readOnly: true,
            title: OrdersStrings.gridPrice,
            field: EshopColumnIds.HISTORY_PRICE,
            type: TrinaColumnType.text(),
            textAlign: TrinaColumnTextAlign.end,
            width: 160,
          ),
        ],
        EshopColumnIds.HISTORY_CHANGES_SUMMARY: [
          TrinaColumn(
            title: OrdersStrings.gridChanges,
            field: EshopColumnIds.HISTORY_CHANGES_SUMMARY,
            type: TrinaColumnType.text(),
            readOnly: true,
            width: 600,
            renderer: (rendererContext) {
              final historyModel = rendererContext
                  .row
                  .cells[EshopColumnIds.HISTORY_MODEL_REFERENCE]
                  ?.value as OrderHistoryModel?;
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
      Color Function(String) getBackground,
      {String? label,
      Future<void> Function()? onChanged,
      int? occasionId, void Function(int, String)? onOpenDetail}) {
    String value = rendererContext.cell.value;
    String firstPart = value.split(";")[0];
    String textValue =
        OrderModel.statesDataGridToUpper(label ?? value.split(";").last);

    return OrderStateCell(
      label: textValue,
      background: getBackground(firstPart),
      onChanged: onChanged,
      onOpenEmails: onOpenDetail == null ? null : () => onOpenDetail(OrderGridFilters.order(rendererContext.row)!.id!, 'emails'),
      occasionId: occasionId,
      order: OrderGridFilters.order(rendererContext.row),
      expired: firstPart == OrderModel.expiredState,
    );
  }

  static TrinaColumn genericTextColumn(String title, String field,
      {bool alignToEnd = true, bool enableEditing = false}) {
    return TrinaColumn(
      readOnly: !enableEditing,
      checkReadOnly: (row, _) =>
          !enableEditing || !OrderGridFilters.ticketIsNonCancelled(row),
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
      {int? unitId, String? orderSymbol}) async {
    await showDialog(
      context: context,
      builder: (BuildContext context) {
        return TransactionsDialog(
          orderId: orderId,
          orderSymbol: orderSymbol,
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
