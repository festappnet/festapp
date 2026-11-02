import 'package:easy_localization/easy_localization.dart';
import 'package:fstapp/components/features/feature_constants.dart';
import 'package:fstapp/components/features/feature_service.dart';

import 'orders_strings.dart';

/// Labels selected from the current occasion's ticket feature.
abstract final class OrderItemStrings {
  static String get cancelAction => 'FeatureOrders.cancel'.tr();

  static String get itemsPlural {
    if (FeatureService.isFeatureEnabled(FeatureConstants.ticket)) {
      return OrdersStrings.tickets;
    }
    return OrdersStrings.applications;
  }

  static String get itemSingular {
    if (FeatureService.isFeatureEnabled(FeatureConstants.ticket)) {
      return OrdersStrings.ticket;
    }
    return OrdersStrings.application;
  }

  static String get sendActionText {
    if (FeatureService.isFeatureEnabled(FeatureConstants.ticket)) {
      return 'FeatureOrders.sendTickets'.tr(); // "Send tickets"
    }
    return 'FeatureOrders.sendConfirmations'.tr(); // "Send confirmations"
  }

  static String get cancelOrdersConfirmationText {
    if (FeatureService.isFeatureEnabled(FeatureConstants.ticket)) {
      return 'FeatureOrders.cancelOrdersAndTicketsConfirmation'.tr(); // "Do you want to cancel orders and all included tickets? The customer will receive an email about this cancellation."
    }
    return 'FeatureOrders.cancelOrdersConfirmation'.tr(); // "Do you want to cancel orders? The customer will receive an email about this cancellation."
  }

  static String get itemSymbol {
    if (FeatureService.isFeatureEnabled(FeatureConstants.ticket)) {
      return 'FeatureOrders.ticketSymbol'.tr(); // "Ticket Symbol"
    }
    return 'FeatureOrders.applicationSymbol'.tr(); // "Application Symbol"
  }

  static String get sendActionConfirmationText {
    if (FeatureService.isFeatureEnabled(FeatureConstants.ticket)) {
      return 'FeatureOrders.sendTicketsToOrdersConfirmation'
          .tr(); // "Do you want to send the tickets to orders?"
    }
    return 'FeatureOrders.sendConfirmationsToOrdersConfirmation'
        .tr(); // "Do you want to send the confirmations to orders?"
  }

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

  static String get validTickets =>
      FeatureService.isFeatureEnabled(FeatureConstants.ticket)
      ? "OrderGridColumns.validTickets".tr()
      : "OrderGridColumns.validApplications".tr();
}
