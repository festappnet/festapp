/// Stable grid field identifiers, shared by row adapters and renderers.
abstract final class EshopColumnIds {
  static const String TICKET_ORIGIN = 'ticketOrigin';
  static const String TICKET_BATCH = 'ticketBatch';
  static const String TICKET_SALE_STATE = 'ticketSaleState';
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
  static const String TICKET_MODEL_REFERENCE = "ticketModelReference";

  static const String TICKET_CREATED_AT = "ticketCreatedAt";
  static const String TICKET_LAST_CHANGE = "ticketLastChangedAt";
  static const String TICKET_SPOT = "ticketSpot";

  static const String ORDER_ID = "orderId";
  static const String ORDER_PRICE = "orderPrice";
  static const String ORDER_WAITLIST = "orderWaitlist";
  static const String ORDER_STATE = "orderState";
  static const String ORDER_MODEL_REFERENCE = "orderModelReference";

  static const String PRODUCT_ID = "productId";
  static const String PRODUCT_TITLE = "productTitle";
  static const String PRODUCT_SHORT_TITLE = "productShortTitle";
  static const String PRODUCT_PRICE_CHANGES = "productPriceChanges";
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

  static const String ORDER_SEQUENCE = "orderSequence";
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

  static const String ORDER_EMAIL_DELIVERY = "orderEmailDelivery";
  static const String HISTORY_ID = "historyId";
  static const String HISTORY_ORDER_SYMBOL = "historyOrderSymbol";
  static const String HISTORY_CHANGED_AT = "historyChangedAt";
  static const String HISTORY_CHANGED_BY = "historyChangedBy";
  static const String HISTORY_STATE = "historyState";
  static const String HISTORY_PRICE = "historyPrice";
  static const String HISTORY_CHANGES_SUMMARY = "historyChangesSummary";
  static const String HISTORY_MODEL_REFERENCE = "historyModelReference";
  static const String ORDER_OVERVIEW = "orderOverview";
}
