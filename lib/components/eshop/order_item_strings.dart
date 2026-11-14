import 'package:easy_localization/easy_localization.dart';
import 'package:fstapp/components/features/feature_service.dart';

/// Labels selected from the current occasion's ticket feature.
abstract final class OrderItemStrings {
  /// Resolve reusable UI copy against the same occasion-level terminology.
  /// Application variants are authored translations, never word replacement.
  static String text(
    String key, {
    bool? hasTickets,
    Map<String, String>? namedArgs,
    List<String>? args,
  }) {
    final applicationKey = 'ApplicationTerminology.$key';
    final resolved =
        !(hasTickets ?? FeatureService.usesTicketTerminology()) &&
            trExists(applicationKey)
        ? applicationKey
        : key;
    return resolved.tr(namedArgs: namedArgs, args: args);
  }

  static String singular(bool hasTickets) => hasTickets
      ? 'FeatureOrders.ticket'.tr()
      : 'FeatureOrders.application'.tr();

  static String get cancelAction => 'FeatureOrders.cancel'.tr();

  static String get itemsPlural {
    if (FeatureService.usesTicketTerminology()) {
      return 'FeatureOrders.tickets'.tr();
    }
    return 'FeatureOrders.applications'.tr();
  }

  static String get itemSingular {
    if (FeatureService.usesTicketTerminology()) {
      return 'FeatureOrders.ticket'.tr();
    }
    return 'FeatureOrders.application'.tr();
  }

  static String get sendActionText {
    if (FeatureService.usesTicketTerminology()) {
      return 'FeatureOrders.sendTickets'.tr(); // "Send tickets"
    }
    return 'FeatureOrders.sendConfirmations'.tr(); // "Send confirmations"
  }

  static String get saveSendActionText => FeatureService.usesTicketTerminology()
      ? 'EmailDelivery.recovery.saveSendTickets'.tr()
      : 'EmailDelivery.recovery.saveSendConfirmation'.tr();

  static String get cancelOrdersConfirmationText {
    if (FeatureService.usesTicketTerminology()) {
      return 'FeatureOrders.cancelOrdersAndTicketsConfirmation'.tr(); // "Do you want to cancel orders and all included tickets? The customer will receive an email about this cancellation."
    }
    return 'FeatureOrders.cancelOrdersConfirmation'.tr(); // "Do you want to cancel orders? The customer will receive an email about this cancellation."
  }

  static String get itemSymbol {
    if (FeatureService.usesTicketTerminology()) {
      return 'FeatureOrders.ticketSymbol'.tr(); // "Ticket Symbol"
    }
    return 'FeatureOrders.applicationSymbol'.tr(); // "Application Symbol"
  }

  static String get sendActionConfirmationText {
    if (FeatureService.usesTicketTerminology()) {
      return 'FeatureOrders.sendTicketsToOrdersConfirmation'
          .tr(); // "Do you want to send the tickets to orders?"
    }
    return 'FeatureOrders.sendConfirmationsToOrdersConfirmation'
        .tr(); // "Do you want to send the confirmations to orders?"
  }

  static String get scanActionText {
    if (FeatureService.usesTicketTerminology()) {
      return 'FeatureOrders.scanTickets'.tr(); // "Scan tickets"
    }
    return 'FeatureOrders.scanEntries'.tr(); // "Scan applications"
  }

  static String get cancelItemsConfirmationText {
    if (FeatureService.usesTicketTerminology()) {
      return 'FeatureOrders.cancelTicketsConfirmation'
          .tr(); // "Do you want to cancel the selected tickets?"
    }
    return 'FeatureOrders.cancelItemsConfirmation'
        .tr(); // "Do you want to cancel the selected items?"
  }

  static String get validTickets => FeatureService.usesTicketTerminology()
      ? "OrderGridColumns.validTickets".tr()
      : "OrderGridColumns.validApplications".tr();

  // Contextual UI copy stays outside model and grid localization contracts.
  static String get waveAvailabilityHideHint =>
      text('FeatureOrders.waveAvailabilityHideHint');

  static String get waveAvailabilityHelp =>
      text('FeatureOrders.waveAvailabilityHelp');

  static String get provideScanLinkInstruction =>
      text('FeatureOrders.provideScanLinkInstruction'); // "Provide the following link or code to the people who will be checking the tickets."

  static String get ticketUsage =>
      text('FeatureOrders.ticketUsage'); // "Ticket usage"

  static String get scanInstructionsAppUser =>
      text('FeatureOrders.scanInstructionsAppUser'); // "Tip: Users can show their QR code from their ticket or directly from the mobile app Profile."

  static String get confirmTicketFailed =>
      text('FeatureOrders.confirmTicketFailed'); // "Failed to confirm ticket"

  static String get dialogTitleFallback =>
      text('ProductsDialog.dialogTitleFallback'); // "Ticket products"

  static String get infoTicketSymbol =>
      text('ProductsDialog.infoTicketSymbol'); // "Ticket Symbol"

  static String get cancelledTicketsTitle =>
      text('ProductsDialog.cancelledTicketsTitle');

  static String get removedTicketsTitle =>
      text('ProductsDialog.removedTicketsTitle');

  static String get addedTicketsTitle =>
      text('ProductsDialog.addedTicketsTitle');

  static String changeTicketLabel(String symbol) =>
      text('ProductsDialog.changeTicketLabel', namedArgs: {'symbol': symbol});

  static String productChangesForTicket(String symbol) => text(
    'ProductsDialog.productChangesForTicket',
    namedArgs: {'symbol': symbol},
  );

  static String get cancelTicketPrefix =>
      text('ProductsDialog.cancelTicketPrefix'); // "CANCEL TICKET "

  static String get globalChangesNote => text(
    'ProductsDialog.globalChangesNote',
  ); // "Note: This includes changes from all tickets in this order."
}
