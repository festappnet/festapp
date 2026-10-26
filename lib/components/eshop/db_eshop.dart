import 'package:fstapp/app_config.dart';
import 'package:fstapp/data_services/rights_service.dart';
import 'package:festapp_core/eshop.dart';
import 'package:collection/collection.dart';
import 'package:material_ui/material_ui.dart';
import 'package:fstapp/components/eshop/eshop_commands.dart';
import 'package:fstapp/components/eshop/supabase_eshop_commands.dart';
import 'package:fstapp/components/eshop/supabase_product_schedule_commands.dart';
import 'package:fstapp/components/inventory/models/inventory_context_model.dart';
import 'package:fstapp/components/inventory/models/inventory_pool_model.dart';
import 'package:fstapp/components/inventory/models/resource_model.dart';
import 'package:fstapp/data_services/client_sync/client_sync_runtime.dart';
import 'package:fstapp/components/eshop/models/order_model.dart';
import 'package:fstapp/components/eshop/models/payment_info_model.dart';
import 'package:fstapp/components/eshop/models/product_edit_bundle.dart';
import 'package:fstapp/services/app_logger.dart';
import 'package:fstapp/components/eshop/models/ticket_model.dart';
import 'package:fstapp/components/eshop/models/transaction_model.dart';
import 'package:fstapp/components/forms/models/form_bundle.dart';
import 'package:fstapp/services/toast_helper.dart';
import 'package:fstapp/components/users/user_info_model.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class DbEshop {
  static final _supabase = Supabase.instance.client;
  static Map<String, dynamic> _productScope() {
    final occasion = RightsService.currentOccasionId();
    if (occasion == null) throw StateError('Product occasion required');
    return {
      'p_occasion': occasion,
      'p_organization': AppConfig.organization,
      'p_unit': RightsService.currentUnit()?.id,
    };
  }

  static EshopCommands get commands =>
      SupabaseEshopCommands(_supabase, productScope: _productScope);
  static SupabaseProductScheduleCommands get scheduleCommands =>
      SupabaseProductScheduleCommands(_supabase, productScope: _productScope);
  static void _checkScheduleLink(String link) {
    if (RightsService.currentOccasion()?.link != link) {
      throw StateError('Product occasion changed');
    }
  }

  static Future<FunctionResponse> sendTicketOrderUpdateEmail(
      int orderId) async {
    final body = {
      "code": "TICKET_ORDER_UPDATE",
      "data": {"orderId": orderId},
    };

    final response = await _supabase.functions.invoke(
      "send-email",
      body: body,
    );

    return response;
  }

  static Future<ReportExchangeRates> getReportExchangeRates() async {
    final result = await _supabase.functions.invoke('report-exchange-rates');
    return ReportExchangeRates.fromJson(Map<String, dynamic>.from(result.data));
  }

  static Future<OccasionReport> getReportForOccasion(String link) async {
    final response =
        await _supabase.rpc('get_report_ws', params: {'occasion_link': link});
    return OccasionReport.fromResponse(response);
  }

  /// Retrieves all transactions associated with a specific order ID.
  static Future<GetTransactionsForOrderResponse?> getTransactionsForOrder(
      int orderId) async {
    final response = await _supabase.rpc(
      'get_transactions_for_order',
      params: {'order_id': orderId},
    );

    if (response != null) {
      return GetTransactionsForOrderResponse.fromJson(response);
    }

    return null;
  }

  /// Retrieves all transactions that have the same bank account as the order's payment_info
  /// and have a NULL payment_info field.
  static Future<List<TransactionModel>?> getTransactionsForOrderAllAvailable(
      int paymentInfoId) async {
    final response = await _supabase.rpc(
      'get_transactions_for_order_all_available',
      params: {'payment_info_id': paymentInfoId},
    );

    if (response != null) {
      return List<TransactionModel>.from(
          response.map((x) => TransactionModel.fromJson(x)));
    }

    return null;
  }

  /// Adds a transaction to payment_info with security checks using RPC.
  static Future<void> addTransactionToPaymentInfoWithSecurity(
      BuildContext context, int transactionId, int paymentInfoId) async {
    try {
      await _supabase.rpc(
        'add_transaction_to_payment_info_ws',
        params: {
          'p_transaction_id': transactionId,
          'p_payment_info_id': paymentInfoId,
        },
      );
    } catch (e) {
      ToastHelper.Show(context, e.toString());
      rethrow;
    }
  }

  /// Removes a transaction from payment_info with security checks using RPC.
  static Future<void> removeTransactionFromPaymentInfoWithSecurity(
      BuildContext context, int transactionId, int paymentInfoId) async {
    try {
      await _supabase.rpc(
        'remove_transaction_from_payment_info_ws',
        params: {
          'p_transaction_id': transactionId,
          'p_payment_info_id': paymentInfoId,
        },
      );
    } catch (e) {
      ToastHelper.Show(context, e.toString());
      rethrow;
    }
  }

  /// Deletes a manual transaction completely from the database using RPC.
  static Future<void> deleteManualTransactionWithSecurity(
      BuildContext context, int transactionId, int paymentInfoId) async {
    try {
      await _supabase.rpc(
        'delete_manual_transaction_ws',
        params: {
          'p_transaction_id': transactionId,
          'p_payment_info_id': paymentInfoId,
        },
      );
    } catch (e) {
      ToastHelper.Show(context, e.toString());
      rethrow;
    }
  }

  static Future<List<ProductModel>?> getProductsForTicketAllAvailable(
      int ticketId) async {
    final result = await _supabase.rpc('get_products_for_ticket_all_available',
        params: {'ticket_id': ticketId});
    if (result != null && result['code'] == 200) {
      return (result['data'] as List)
          .map((e) => ProductModel.fromJson(e as Map<String, dynamic>))
          .toList();
    } else {
      return [];
    }
  }

  static Future<TicketDetailsBundle?> getProductsForTicket(int ticketId) async {
    final response = await _supabase
        .rpc('get_products_for_ticket', params: {'ticket_id': ticketId});

    if (response != null && response['code'] == 200) {
      final data = response['data'];
      return TicketDetailsBundle.fromJson(data);
    }
    return null;
  }

  static Future<dynamic> updateProductsForOrder(
      int ticketId, List<ProductModel> products) {
    final productsJson =
        products.map((p) => {'id': p.id, 'price': p.price}).toList();

    if (ClientSyncRuntime.isV1Selected) {
      return commands.updateTicketProducts(ticketId, productsJson);
    }

    // Directly return the Future. The calling code will handle success or exceptions.
    return _supabase.rpc(
      'update_ticket_products_wsv2',
      params: {
        'p_ticket_id': ticketId,
        'p_products': productsJson,
      },
    );
  }

  static Future<ProductsEditBundle> getProductsAndTypesForOccasion(
      String occasionLink) async {
    final catalogResponse = await _supabase.rpc(
      'get_product_catalog',
      params: {
        'p_occasion_link': occasionLink,
        'p_organization': AppConfig.organization,
      },
    );
    final response = catalogResponse['catalog'];

    // Parse all data lists from the response
    final types = (response['product_types'] as List)
        .map((t) => ProductTypeModel.fromJson(t))
        .toList();
    final products = (response['products'] as List)
        .map((p) => ProductModel.fromJson(p))
        .toList();
    final pools = (response['inventory_pools'] as List)
        .map((p) => InventoryPoolModel.fromJson(p))
        .toList();
    final contexts = (response['inventory_contexts'] as List)
        .map((c) => InventoryContextModel.fromJson(c))
        .toList();
    final productContextLinks = (response['product_inventory_contexts'] as List)
        .map((pc) => ProductInventoryContextModel.fromJson(pc))
        .toList();
    final forms =
        (response['forms'] as List).map((f) => FormBundle.fromJson(f)).toList();

    // Create lookup maps for efficient joins
    final poolsMap = {for (var p in pools) p.id: p};
    final contextsMap = {for (var c in contexts) c.id: c};
    final formsMap = {
      for (var form in forms) form.definition.id: form.definition.toString()
    };

    // Join inventory pools to inventory contexts
    for (var context in contexts) {
      context.inventoryPool = poolsMap[context.inventoryPoolId];
    }

    // Group inventory links by product ID
    final productLinksMap =
        groupBy(productContextLinks, (link) => link.productId);

    final serverTime = DateTime.parse(response['server_time']).toUtc();
    final clockOffset = serverTime.difference(DateTime.now().toUtc());
    for (var index = 0; index < products.length; index++) {
      final product = products[index];
      products[index] = product.copyWith(
        priceServerTime: serverTime,
        priceClockOffset: clockOffset,
        includedInventories: (productLinksMap[product.id] ?? [])
            .where((link) => contextsMap.containsKey(link.inventoryContextId))
            .toList(),
        formTitles: product.formIds.map((id) => formsMap[id]).join(', '),
      );
    }

    products.sort((a, b) {
      final aType = a.productTypeId ?? 0;
      final bType = b.productTypeId ?? 0;
      if (aType != bType) return aType.compareTo(bType);
      final aOrder = a.order ?? 0;
      final bOrder = b.order ?? 0;
      return aOrder.compareTo(bOrder);
    });

    return ProductsEditBundle(
      products: products,
      priceWaves: (response['price_waves'] as List? ?? [])
          .map((w) => ProductPriceWave.fromJson(w))
          .toList(),
      productTypes: types,
      inventoryPools: pools,
      inventoryContexts: contexts,
      forms: forms,
    );
  }

  static Future<ProductPriceWave> createProductPriceWave(
      String link, DateTime time) async {
    _checkScheduleLink(link);
    return scheduleCommands.ensureWave(time);
  }

  static Future<void> saveNewProductWaveTarget(
      String occasionLink,
      ProductPriceWave wave,
      int productId,
      double? price,
      bool? hidden,
      int? priceRevision,
      int? visibilityRevision) async {
    _checkScheduleLink(occasionLink);
    await scheduleCommands.saveTarget(
        wave, productId, price, hidden, priceRevision, visibilityRevision);
  }

  static Future<void> saveProductWaveTarget(
          ProductPriceWave wave,
          int productId,
          double? price,
          bool? hidden,
          int? priceRevision,
          int? visibilityRevision) =>
      scheduleCommands.saveTarget(
          wave, productId, price, hidden, priceRevision, visibilityRevision);

  static Future<void> moveProductPriceWave(
          ProductPriceWave wave, DateTime time) =>
      scheduleCommands.moveWave(wave, time);
  static Future<void> cancelProductPriceWave(ProductPriceWave wave) =>
      scheduleCommands.cancelWave(wave);
  static Future<void> saveProductPriceChange(
          int productId, double price, DateTime time,
          {int? changeId, int? revision}) =>
      scheduleCommands.savePriceChange(productId, price, time,
          changeId: changeId, revision: revision);
  static Future<void> cancelProductPriceChange(
          int productId, int changeId, int revision) =>
      scheduleCommands.cancelPriceChange(productId, changeId, revision);

  static Future<ProductModel> saveProductBasics(ProductModel product) async {
    final saved = await commands.saveProduct({
      'id': product.id,
      'title': product.title,
      'price': product.price,
      if (product.id == null) ...{
        'product_type': product.productTypeId,
        'occasion': product.occasion,
        'currency_code': product.currencyCode,
      },
      if (product.id != null)
        'expected_aggregate_version': product.aggregateVersion,
    });
    return product.copyWith(
        id: saved.id, aggregateVersion: saved.aggregateVersion);
  }

  /// Fetches all resources associated with a specific inventory pool ID.
  static Future<List<ResourceModel>> getResourcesForInventoryPool(
      int inventoryPoolId) async {
    try {
      final response = await _supabase.rpc(
        'get_resources_for_inventory_pool_v1',
        params: {'p_inventory_pool_id': inventoryPoolId},
      );

      // The RPC function returns a list of resource objects.
      // We cast the response and map each item to our ResourceModel.
      if (response != null) {
        return (response as List)
            .map((data) => ResourceModel.fromJson(data as Map<String, dynamic>))
            .toList();
      }
    } catch (e) {
      AppLogger.error('Error fetching resources for pool $inventoryPoolId: $e');
      // Depending on your error handling strategy, you might want to show a toast.
      // For now, we return an empty list to prevent crashes.
    }
    return [];
  }
}

// DATA MODELS

class GetTransactionsForOrderResponse {
  final String? orderState;
  final PaymentInfoModel? paymentInfo;
  final List<TransactionModel> transactions;

  GetTransactionsForOrderResponse({
    this.orderState,
    required this.paymentInfo,
    required this.transactions,
  });

  factory GetTransactionsForOrderResponse.fromJson(Map<String, dynamic> json) {
    // Parse users
    final users = json['users'] != null
        ? List<UserInfoModel>.from(
            (json['users'] as List).map((x) => UserInfoModel.fromJson(x)))
        : <UserInfoModel>[];

    // Create user map
    final userMap = {for (var u in users) u.id: u};

    final transactions = json['transactions'] != null
        ? List<TransactionModel>.from(
            json['transactions'].map((x) => TransactionModel.fromJson(x)))
        : <TransactionModel>[];

    // Link users
    for (var t in transactions) {
      t.createdBy = userMap[t.createdById];
    }

    return GetTransactionsForOrderResponse(
      orderState: json['order_state'] as String?,
      paymentInfo: json['payment_info'] != null
          ? PaymentInfoModel.fromJson(json['payment_info'])
          : null,
      transactions: transactions,
    );
  }
}

class OrderHistoryInfo {
  final DateTime? latestSentAt;
  final bool isNewerVersionAvailable;

  OrderHistoryInfo({
    this.latestSentAt,
    required this.isNewerVersionAvailable,
  });

  factory OrderHistoryInfo.fromJson(Map<String, dynamic> json) {
    return OrderHistoryInfo(
      latestSentAt: json['latest_sent_at'] != null
          ? DateTime.parse(json['latest_sent_at'])
          : null,
      isNewerVersionAvailable: json['is_newer_version_available'],
    );
  }
}

class TicketDetailsBundle {
  final TicketModel ticket;
  final OrderModel order;
  final PaymentInfoModel? paymentInfo;
  final OrderHistoryInfo orderHistory;
  final OrderModel? referenceOrder;
  final OrderChangeSummary changes;

  TicketDetailsBundle({
    required this.ticket,
    required this.order,
    this.paymentInfo,
    required this.orderHistory,
    this.referenceOrder,
    required this.changes,
  });

  factory TicketDetailsBundle.fromJson(Map<String, dynamic> json) {
    var bundle = TicketDetailsBundle(
      changes: OrderChangeSummary.fromJson(
          Map<String, dynamic>.from(json['order_changes'])),
      ticket: TicketModel.fromJson(json['ticket']),
      order: OrderModel.fromJson(json['order']),
      paymentInfo: json['payment_info'] != null
          ? PaymentInfoModel.fromJson(json['payment_info'])
          : null,
      orderHistory: OrderHistoryInfo.fromJson(json['order_history']),
      referenceOrder: json['reference_order_data'] != null
          ? OrderModel.fromJson(json['reference_order_data'])
          : null,
    );
    var products = (json['ticket']['products'] as List? ?? [])
        .map((e) => ProductModel.fromJson(e as Map<String, dynamic>))
        .toList();
    bundle.ticket.relatedProducts = products;
    return bundle;
  }
}
