import 'package:easy_localization/easy_localization.dart';
import 'package:fstapp/components/features/feature_constants.dart';
import 'package:fstapp/components/features/feature_service.dart';

class OrdersStrings {
  // --- Orders Tab ---
  static String get synchronizePayments =>
      'FeatureOrders.synchronizePayments'.tr(); // "Synchronize Payments"
  static String get processing =>
      'FeatureOrders.processing'.tr(); // "Processing..."
  static String get failedToSaveProduct =>
      'FeatureOrders.failedToSaveProduct'.tr(); // "Failed to save product."
  static String get failedToDeleteProduct =>
      'FeatureOrders.failedToDeleteProduct'.tr(); // "Failed to delete product."
  static String get changeStateToPaid =>
      'FeatureOrders.changeStateToPaid'.tr(); // "Change state to paid"
  static String get changeStateToPaidConfirmation =>
      'FeatureOrders.changeStateToPaidConfirmation'
          .tr(); // "Do you want to change orders to paid?"
  static String get tickets => 'FeatureOrders.tickets'.tr(); // "Tickets"
  static String get ticket => 'FeatureOrders.ticket'.tr(); // "Ticket"
  static String get addPayment =>
      'FeatureOrders.addPayment'.tr(); // "Add Payment"
  static String get addCashPaymentTitle =>
      'FeatureOrders.addCashPaymentTitle'.tr(); // "Add Cash Payment"
  static String get transactionTypeCash =>
      'FeatureOrders.transactionTypeCash'.tr();
  static String get transactionTypeCashless =>
      'FeatureOrders.transactionTypeCashless'.tr();
  static String get transactionTypeManual =>
      'FeatureOrders.transactionTypeManual'.tr(); // "Cash"
  static String get acceptedBy =>
      'FeatureOrders.acceptedBy'.tr(); // "Accepted by"
  static String get variableSymbol =>
      'FeatureOrders.variableSymbol'.tr(); // "Variable symbol"
  static String get messageForRecipient =>
      'FeatureOrders.messageForRecipient'.tr(); // "Message for Recipient"
  static String get amount => 'FeatureOrders.amount'.tr(); // "Amount"
  static String get paid => 'FeatureOrders.paid'.tr(); // "Paid"
  static String get returned => 'FeatureOrders.returned'.tr(); // "Returned"
  static String get noTransactionsFound =>
      'FeatureOrders.noTransactionsFound'.tr(); // "No transactions found."
  static String get noUnpairedTransactionsFound =>
      'FeatureOrders.noUnpairedTransactionsFound'.tr();
  static String get findAndLinkTransaction =>
      'FeatureOrders.findAndLinkTransaction'
          .tr(); // "Find and link a transaction"
  static String get unlinkTransactionConfirmation =>
      'FeatureOrders.unlinkTransactionConfirmation'
          .tr(); // "Are you sure you want to unlink this transaction?"
  static String get confirmRemoval =>
      'FeatureOrders.confirmRemoval'.tr(); // "Confirm removal"
  static String removeTransactionSuccess(String item) =>
      'FeatureOrders.removeTransactionSuccess'
          .tr(namedArgs: {'item': item}); // "Removed {item}."
  static String get removeTransactionTooltip =>
      'FeatureOrders.removeTooltip'.tr(); // "Remove"
  static String get searchUnpairedTransactions =>
      'FeatureOrders.searchUnpairedTransactions'.tr();
  static String transactionsForOrder(String order) =>
      'FeatureOrders.transactionsForOrder'
          .tr(namedArgs: {'order': order}); // "Transactions for order {order}."
  static String get date => 'FeatureOrders.date'.tr(); // "Date"
  static String get enterCashAmountDescription =>
      'FeatureOrders.enterCashAmountDescription'
          .tr(); // "Enter the amount received from the customer."
  static String get applications =>
      'FeatureOrders.applications'.tr(); // "Applications"
  static String get application =>
      'FeatureOrders.application'.tr(); // "Application"
  static String get stornoFailed =>
      'FeatureOrders.stornoFailed'.tr(); // "Action has failed."
  static String get ordersTab => 'FeatureOrders.ordersTab'.tr(); // "Orders"

  // --- Order States ---
  static String get stateNotSet =>
      'FeatureOrders.stateNotSet'.tr(); // "Not Set"
  static String get stateOrdered =>
      'FeatureOrders.stateOrdered'.tr(); // "Ordered"
  static String get stateSent => 'FeatureOrders.stateSent'.tr(); // "Sent"
  static String get stateUsed => 'FeatureOrders.stateUsed'.tr(); // "Used"

  // --- Transactions ---
  static String get message => 'FeatureOrders.message'.tr(); // "Message"
  static String get notAvailable => 'FeatureOrders.notAvailable'.tr(); // "N/A"
  static String get addTransactionConfirmation =>
      'FeatureOrders.addTransactionConfirmation'
          .tr(); // "Are you sure you want to add this transaction?"
  static String get transactionAddedSuccess =>
      'FeatureOrders.transactionAddedSuccess'
          .tr(); // "Transaction added successfully."
  static String get searchTransactionsHint =>
      'FeatureOrders.searchTransactionsHint'
          .tr(); // "Search by message, account, symbol, name, or amount"

  // --- Products Search ---
  static String get searchProductsHint =>
      'FeatureOrders.searchProductsHint'.tr(); // "By title, type or price"
  static String get noProductsFound =>
      'FeatureOrders.noProductsFound'.tr(); // "No products found."
  static String get noDataToDisplay =>
      'FeatureOrders.noDataToDisplay'.tr(); // "No data to display."

  // --- Scan Code Sharing Dialog ---
  static String get copy => 'FeatureOrders.copy'.tr(); // "Copy"
  static String get copyLink => 'FeatureOrders.copyLink'.tr(); // "Copy Link"
  static String get generateNewCode =>
      'FeatureOrders.generateNewCode'.tr(); // "Generate New Code"
  static String get generateNewCodeWarning => 'FeatureOrders.generateNewCodeWarning'
      .tr(); // "By generating a new code, the old one will be replaced and will no longer work."
  static String get provideScanLinkInstruction =>
      'FeatureOrders.provideScanLinkInstruction'
          .tr(); // "Provide the following link or code to the people who will be checking the tickets."
  static String get ordersHistoryTab =>
      'FeatureOrders.ordersHistoryTab'.tr(); // "Orders History"

  static String get confirmTicket =>
      'FeatureOrders.setAsUsed'.tr(); // "Set as used"
  static String get restoreTicket =>
      'FeatureOrders.setAsUnused'.tr(); // "Set as unused"
  static String get ticketUsage =>
      'FeatureOrders.ticketUsage'.tr(); // "Ticket usage"

  // --- Tickets/Items Tab ---
  static String stornoCompleted({required String item}) =>
      'FeatureOrders.stornoCompletedItem'
          .tr(namedArgs: {'item': item}); // "Storno completed for {item}."

  /// Returns "Tickets" or "Applications" based on whether the ticket feature is enabled.
  static String get itemsPlural {
    if (FeatureService.isFeatureEnabled(FeatureConstants.ticket)) {
      return tickets;
    }
    return applications;
  }

  /// Returns "Ticket" or "Application" based on whether the ticket feature is enabled.
  static String get itemSingular {
    if (FeatureService.isFeatureEnabled(FeatureConstants.ticket)) {
      return ticket;
    }
    return application;
  }

  /// Returns "Send tickets" or "Send confirmations" based on whether the ticket feature is enabled.
  static String get sendActionText {
    if (FeatureService.isFeatureEnabled(FeatureConstants.ticket)) {
      return 'FeatureOrders.sendTickets'.tr(); // "Send tickets"
    }
    return 'FeatureOrders.sendConfirmations'.tr(); // "Send confirmations"
  }

  /// Returns confirmation text for cancelling orders, with or without mentioning tickets.
  static String get cancelOrdersConfirmationText {
    if (FeatureService.isFeatureEnabled(FeatureConstants.ticket)) {
      return 'FeatureOrders.cancelOrdersAndTicketsConfirmation'
          .tr(); // "Do you want to cancel orders and all included tickets? The customer will receive an email about this cancellation."
    }
    return 'FeatureOrders.cancelOrdersConfirmation'
        .tr(); // "Do you want to cancel orders? The customer will receive an email about this cancellation."
  }

  static String get itemSymbol {
    if (FeatureService.isFeatureEnabled(FeatureConstants.ticket)) {
      return 'FeatureOrders.ticketSymbol'.tr(); // "Ticket Symbol"
    }
    return 'FeatureOrders.applicationSymbol'.tr(); // "Application Symbol"
  }

  /// Returns confirmation text for sending tickets/confirmations.
  static String get sendActionConfirmationText {
    if (FeatureService.isFeatureEnabled(FeatureConstants.ticket)) {
      return 'FeatureOrders.sendTicketsToOrdersConfirmation'
          .tr(); // "Do you want to send the tickets to orders?"
    }
    return 'FeatureOrders.sendConfirmationsToOrdersConfirmation'
        .tr(); // "Do you want to send the confirmations to orders?"
  }

  // --- Scan Page Specific ---
  // (Scan-specific labels moved to ScanStrings in lib/components/scan/scan_strings.dart)
  static String get scanInstructionsAppUser =>
      'FeatureOrders.scanInstructionsAppUser'
          .tr(); // "Tip: Users can show their QR code from their ticket or directly from the mobile app Profile."
  static String get scanningForOccasion =>
      'FeatureOrders.scanningForOccasion'.tr(); // "Scanning for: "

  // New Migrated Strings (previously hardcoded in Czech)
  static String get bigGameLabel =>
      'FeatureOrders.bigGameLabel'.tr(); // "Big Game: "
  static String get selectAttendee =>
      'FeatureOrders.selectAttendee'.tr(); // "Select attendee"
  static String get searchPlaceholder =>
      'FeatureOrders.searchPlaceholder'.tr(); // "Search (name, email)..."
  static String get newLoginCredentials =>
      'FeatureOrders.newLoginCredentials'.tr(); // "New login credentials"
  static String get errorEmailNotReturned =>
      'FeatureOrders.errorEmailNotReturned'
          .tr(); // "Error: Email was not returned."
  static String get errorResetPasswordPrivilegedUser =>
      'FeatureOrders.errorResetPasswordPrivilegedUser'.tr();
  static String get confirmTicketFailed =>
      'FeatureOrders.confirmTicketFailed'.tr(); // "Failed to confirm ticket"

  static String get scanNotFound =>
      'FeatureOrders.scanNotFound'.tr(); // "Invalid code" (Neplatný kód)

  // --- Deposit Scan Info ---
  static String get scanDepositRemaining =>
      'FeatureOrders.scanDepositRemaining'.tr(); // "Deposit remaining"
  static String get scanDepositFullyPaid =>
      'FeatureOrders.scanDepositFullyPaid'.tr(); // "Fully paid"
  static String get scanDepositDeadline =>
      'FeatureOrders.scanDepositDeadline'.tr(); // "Deadline"
  static String get scanDepositOnSite =>
      'FeatureOrders.scanDepositOnSite'.tr(); // "Pay on site"
  static String get scanDepositCollect =>
      'FeatureOrders.scanDepositCollect'.tr(); // "Collect remaining"

  // Backward compatibility aliases
  static String get scanSurchargeRemaining => scanDepositRemaining;
  static String get scanSurchargeFullyPaid => scanDepositFullyPaid;
  static String get scanSurchargeDeadline => scanDepositDeadline;
  static String get scanSurchargeOnSite => scanDepositOnSite;
  static String get scanSurchargeCollect => scanDepositCollect;

  // Specific Field Mappings (previously hardcoded)
  static String get fieldTypeParticipant =>
      'FeatureOrders.fieldTypeParticipant'.tr(); // "Participant Type"
  static String get fieldMemberAnima =>
      'FeatureOrders.fieldMemberAnima'.tr(); // "Member of Anima Iuventutis"
  static String get fieldDietary =>
      'FeatureOrders.fieldDietary'.tr(); // "Dietary restrictions"
  static String get fieldPrepTeam =>
      'FeatureOrders.fieldPrepTeam'.tr(); // "Preparatory team"

  // Dynamic Methods
  static String resetPasswordTo(String password) =>
      'FeatureOrders.resetPasswordTo'.tr(namedArgs: {
        'password': password
      }); // "Reset password to '{password}'"
  static String resetPasswordConfirmationContent(String password) =>
      'FeatureOrders.resetPasswordConfirmationContent'.tr(namedArgs: {
        'password': password
      }); // "Are you sure you want to change the password to '{password}'?"
  static String errorResetPassword(String error) =>
      'FeatureOrders.errorResetPassword'.tr(
          namedArgs: {'error': error}); // "Error resetting password: {error}"

  // Tickets Tab
  static String get scanActionText {
    if (FeatureService.isFeatureEnabled(FeatureConstants.ticket)) {
      return 'FeatureOrders.scanTickets'.tr(); // "Scan tickets"
    }
    return 'FeatureOrders.scanEntries'.tr(); // "Scan applications"
  }

  static String get cancelItemsConfirmationText {
    if (FeatureService.isFeatureEnabled(FeatureConstants.ticket)) {
      return 'FeatureOrders.cancelTicketsConfirmation'
          .tr(); // "Do you want to cancel the selected tickets?"
    }
    return 'FeatureOrders.cancelItemsConfirmation'
        .tr(); // "Do you want to cancel the selected items?"
  }

  // --- Order Grid Columns ---
  static String get gridId => 'OrderGridColumns.id'.tr(); // "Id"
  static String get gridHide => 'OrderGridColumns.hide'.tr(); // "Hide"
  static String get gridTitle => 'OrderGridColumns.title'.tr(); // "Title"
  static String get gridPrice => 'OrderGridColumns.price'.tr(); // "Price"
  static String get gridProductType =>
      'OrderGridColumns.productType'.tr(); // "Product Type"
  static String get gridOrder => 'OrderGridColumns.order'.tr(); // "Order"
  static String get gridMax => 'OrderGridColumns.max'.tr(); // "Max"
  static String get gridOrdered => 'OrderGridColumns.ordered'.tr(); // "Ordered"
  static String get gridPaid => 'OrderGridColumns.paid'.tr(); // "Paid"
  static String get gridCurrency =>
      'OrderGridColumns.currency'.tr(); // "Currency"
  static String get gridDescription =>
      'OrderGridColumns.description'.tr(); // "Description"
  static String get gridState => 'OrderGridColumns.state'.tr(); // "State"
  static String get gridCreated => 'OrderGridColumns.created'.tr(); // "Created"
  static String get gridProducts =>
      'OrderGridColumns.products'.tr(); // "Products"
  static String get gridNote => 'OrderGridColumns.note'.tr(); // "Note"
  static String get gridHiddenNote =>
      'OrderGridColumns.hiddenNote'.tr(); // "Hidden note"
  static String get gridSpot => 'OrderGridColumns.spot'.tr(); // "Spot"
  static String get gridOrderSymbol =>
      'OrderGridColumns.orderSymbol'.tr(); // "Order Symbol"
  static String get gridCustomer =>
      'OrderGridColumns.customer'.tr(); // "Customer"
  static String get gridEmail => 'OrderGridColumns.email'.tr(); // "E-mail"
  static String get gridHistory => 'OrderGridColumns.history'.tr(); // "History"
  static String get gridTransactions =>
      'OrderGridColumns.transactions'.tr(); // "Transactions"
  static String get gridAmount => 'OrderGridColumns.amount'.tr(); // "Amount"
  static String get gridReturned =>
      'OrderGridColumns.returned'.tr(); // "Returned"
  static String get gridVariableSymbol =>
      'OrderGridColumns.variableSymbol'.tr(); // "Variable symbol"
  static String get gridDeadline =>
      'OrderGridColumns.deadline'.tr(); // "Deadline"
  static String get gridForm => 'OrderGridColumns.form'.tr(); // "Form"
  static String get gridReminderSent =>
      'OrderGridColumns.reminderSent'.tr(); // "Reminder Sent"
  static String get gridChangedAt =>
      'OrderGridColumns.changedAt'.tr(); // "Changed At"
  static String get gridChangedBy =>
      'OrderGridColumns.changedBy'.tr(); // "Changed By"
  static String get gridChanges => 'OrderGridColumns.changes'.tr(); // "Changes"
  static String get gridPaidOrSent =>
      'OrderGridColumns.paidOrSent'.tr(); // "Paid or Sent"
  static String get gridCancelled =>
      'OrderGridColumns.cancelled'.tr(); // "Cancelled"
  static String get gridUsedInForms =>
      'OrderGridColumns.usedInForms'.tr(); // "Used in Forms"
  static String get gridShortTitle =>
      'OrderGridColumns.shortTitle'.tr(); // "Short Title"
  static String get gridSurcharge => 'OrderGridColumns.surcharge'.tr();
  static String get gridDeposit => 'OrderGridColumns.deposit'.tr();
  static String get gridDepositDeadline =>
      'OrderGridColumns.depositDeadline'.tr();
  static String get gridDepositPaymentDeadline =>
      'OrderGridColumns.depositPaymentDeadline'.tr();
  static String get gridDepositOnSiteLabel =>
      'OrderGridColumns.depositOnSiteLabel'.tr();

  // --- PDF Generation Strings ---
  static String get generatingPdf =>
      'FeatureOrders.generatingPdf'.tr(); // "Generating PDF..."
  static String get downloadTicket =>
      'FeatureOrders.downloadTicket'.tr(); // "Download Ticket"
  static String generatingPdfFor(String customer) =>
      'FeatureOrders.generatingPdfFor'.tr(namedArgs: {
        'customer': customer
      }); // "Generating PDF for {customer}..."
  static String generatingPdfForWithSpot(String customer, String spot) =>
      'FeatureOrders.generatingPdfForWithSpot'.tr(namedArgs: {
        'customer': customer,
        'spot': spot
      }); // "Generating PDF for {customer} - {spot}..."

  // --- Products Dialog ---
  static String get productsUpdateSuccess =>
      'ProductsDialog.productsUpdateSuccess'
          .tr(); // "Products updated successfully."
  static String get productsUpdateFailed =>
      'ProductsDialog.productsUpdateFailed'
          .tr(); // "Failed to update products."
  static String get sendUpdateTitle =>
      'ProductsDialog.sendUpdateTitle'.tr(); // "Send Update to Customer?"
  static String sendUpdateContent(String email) =>
      'ProductsDialog.sendUpdateContent'.tr(namedArgs: {
        'email': email
      }); // "This will send an email to {email} with:"
  static String get sendUpdateItemSummary =>
      'ProductsDialog.sendUpdateItemSummary'.tr(); // "Updated order summary"
  static String get sendUpdateItemStatus =>
      'ProductsDialog.sendUpdateItemStatus'
          .tr(); // "Current payment status and balance"
  static String get sendUpdateItemQr => 'ProductsDialog.sendUpdateItemQr'
      .tr(); // "Payment QR code for the balance due"
  static String get sendUpdateItemRefund =>
      'ProductsDialog.sendUpdateItemRefund'
          .tr(); // "Information that the overpayment will be refunded"
  static String get sendEmailButton =>
      'ProductsDialog.sendEmailButton'.tr(); // "Send Email"
  static String get sendEmailFailed =>
      'ProductsDialog.sendEmailFailed'.tr(); // "Failed to send update email."
  static String get sendEmailSuccess => 'ProductsDialog.sendEmailSuccess'
      .tr(); // "Update email sent successfully."
  static String get dialogTitleFallback =>
      'ProductsDialog.dialogTitleFallback'.tr(); // "Ticket products"
  static String get originalPrice =>
      'ProductsDialog.originalPrice'.tr(); // "Original"
  static String get currentPrice =>
      'ProductsDialog.currentPrice'.tr(); // "Current"
  static String get priceChange =>
      'ProductsDialog.priceChange'.tr(); // "Change"
  static String get noProducts =>
      'ProductsDialog.noProducts'.tr(); // "No products selected."
  static String get addBackTooltip =>
      'ProductsDialog.addBackTooltip'.tr(); // "Add back"
  static String get removeTooltip =>
      'ProductsDialog.removeTooltip'.tr(); // "Remove"
  static String get addProductsButton =>
      'ProductsDialog.addProductsButton'.tr(); // "Add products"
  static String get infoTicketSymbol =>
      'ProductsDialog.infoTicketSymbol'.tr(); // "Ticket Symbol"
  static String get infoEmail => 'ProductsDialog.infoEmail'.tr(); // "Email"
  static String get infoOrderStatus =>
      'ProductsDialog.infoOrderStatus'.tr(); // "Order Status"
  static String get infoPayment =>
      'ProductsDialog.infoPayment'.tr(); // "Payment"
  static String get outdatedTitle =>
      'ProductsDialog.outdatedTitle'.tr(); // "Outdated Confirmation"
  static String get outdatedSubtitle => 'ProductsDialog.outdatedSubtitle'
      .tr(); // "The order has changed since the last email was sent."
  static String get sendUpdateButton =>
      'ProductsDialog.sendUpdateButton'.tr(); // "Send Update to Customer"
  static String get editPriceTooltip =>
      'ProductsDialog.editPriceTooltip'.tr(); // "Edit price"
  static String get editPriceTitle =>
      'ProductsDialog.editPriceTitle'.tr(); // "Edit Price"
  static String get newPriceLabel =>
      'ProductsDialog.newPriceLabel'.tr(); // "New price"
  static String get priceValidationRequired =>
      'ProductsDialog.priceValidationRequired'.tr(); // "Price is required."
  static String get priceValidationInvalid =>
      'ProductsDialog.priceValidationInvalid'
          .tr(); // "Please enter a valid price."
  static String get noProductChangesDetected =>
      'ProductsDialog.noProductChangesDetected'
          .tr(); // "No changes detected to be sent."
  static String get addedProductsTitle =>
      'ProductsDialog.addedProductsTitle'.tr(); // "Added Products:"
  static String get removedProductsTitle =>
      'ProductsDialog.removedProductsTitle'.tr(); // "Removed Products:"
  static String get cancelledItemsTitle =>
      'ProductsDialog.cancelledItemsTitle'.tr(); // "Cancelled Items"
  static String get newOrderTitle =>
      'ProductsDialog.newOrderTitle'.tr(); // "New Order"
  static String get fullCancelLabel =>
      'ProductsDialog.fullCancelLabel'.tr(); // "Full Cancel of Order"
  static String get partialCancelLabel =>
      'ProductsDialog.partialCancelLabel'.tr(); // "Partial Cancel / Modified"
  static String get cancelOrderPrefix =>
      'ProductsDialog.cancelOrderPrefix'.tr(); // "CANCEL ORDER "
  static String get cancelTicketPrefix =>
      'ProductsDialog.cancelTicketPrefix'.tr(); // "CANCEL TICKET "
  static String get willBeRemoved =>
      'ProductsDialog.willBeRemoved'.tr(); // "Entire order will be removed"
  static String get newOrderTotal =>
      'ProductsDialog.newOrderTotal'.tr(); // "New Order Total"
  static String get emailHelpText => 'ProductsDialog.emailHelpText'
      .tr(); // "Enter the customer's email address to send the new order confirmation and payment details."
  static String get noDetailsFound =>
      'ProductsDialog.noDetailsFound'.tr(); // "No details found"
  static String get customerExample =>
      'ProductsDialog.customerExample'.tr(); // "customer@example.com"
  static String get changedPricesTitle =>
      'ProductsDialog.changedPricesTitle'.tr(); // "Changed Prices:"
  static String get emailContentIntro => 'ProductsDialog.emailContentIntro'
      .tr(); // "The email will include the following:"
  static String get setToZeroButton =>
      'ProductsDialog.setToZeroButton'.tr(); // "Set to Zero"
  static String get sendUpdateItemChanges =>
      'ProductsDialog.sendUpdateItemChanges'
          .tr(); // "Overview of product changes"
  static String get priceValidationNegative =>
      'ProductsDialog.priceValidationNegative'
          .tr(); // "Price cannot be negative."
  static String get totalPriceChange =>
      'ProductsDialog.totalPriceChange'.tr(); // "Total Price Change"
  static String get globalChangesNote => 'ProductsDialog.globalChangesNote'
      .tr(); // "Note: This includes changes from all tickets in this order."

  // --- Order History ---
  static String get noHistoryFound =>
      'OrderHistory.noHistoryFound'.tr(); // "No history found"
  static String get currentState =>
      'OrderHistory.currentState'.tr(); // "Current state"
  static String get systemUser => 'OrderHistory.systemUser'.tr(); // "System"
  static String get changes => 'OrderHistory.changes'.tr(); // "Changes"
  static String get totalPrice =>
      'OrderHistory.totalPrice'.tr(); // "Total Price: {price}"
  static String get noProductChanges =>
      'OrderHistory.noProductChanges'.tr(); // "No product changes"
  static String get expiredOrderTooltip =>
      'OrderHistory.expiredOrderTooltip'.tr(); // "Expired order"
  static String get deleteCashTransactionConfirmation =>
      'FeatureOrders.deleteCashTransactionConfirmation'
          .tr(); // "Are you sure you want to delete this cash payment? This will permanently remove it."
  static String toBasicString(int id, int orderId) =>
      'OrderHistory.toBasicString'.tr(namedArgs: {
        "id": id.toString(),
        "orderId": orderId.toString()
      }); // "Item {id} (Order {orderId})"
}
