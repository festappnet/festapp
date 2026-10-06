import 'orders_strings.dart';
import 'package:fstapp/components/features/feature_service.dart';
import 'package:fstapp/components/features/feature_constants.dart';
import 'models/order_model.dart';
import 'package:easy_localization/easy_localization.dart';

class ReportStrings {
  static String get onlyValid => 'OccasionReport.onlyValid'.tr();
  static String get includingCancelled => 'OccasionReport.includingCancelled'.tr();
  static bool get hasTickets =>
      FeatureService.isFeatureEnabled(FeatureConstants.ticket);
  static String state(String? state) =>
      OrderModel.stateToLocale(state == 'unknown' ? null : state);
  static String get ratesUnavailable => 'OccasionReport.ratesUnavailable'.tr();
  static String get compareCurrencies =>
      'OccasionReport.compareCurrencies'.tr();
  static String get currencyComparisonHelp =>
      'OccasionReport.currencyComparisonHelp'.tr();
  static String get orderTimeline => hasTickets
      ? 'OccasionReport.orderTimeline'.tr()
      : 'OccasionReport.applicationTimeline'.tr();
  static String get orderTimelineHelp => hasTickets
      ? 'OccasionReport.orderTimelineHelp'.tr()
      : 'OccasionReport.applicationTimelineHelp'.tr();
  static String get paymentTimeline => 'OccasionReport.paymentTimeline'.tr();
  static String get paymentTimelineHelp =>
      'OccasionReport.paymentTimelineHelp'.tr();
  static String get daily => 'OccasionReport.daily'.tr();
  static String get cumulative => 'OccasionReport.cumulative'.tr();
  static String get allDays => 'OccasionReport.allDays'.tr();
  static String get days30 => 'OccasionReport.days30'.tr();
  static String get days90 => 'OccasionReport.days90'.tr();
  static String get timelineUnavailable =>
      'OccasionReport.timelineUnavailable'.tr();
  static String get timelineEmpty => 'OccasionReport.timelineEmpty'.tr();
  static String get timelineTotal => 'OccasionReport.timelineTotal'.tr();
  static String get recordedPayments => 'OccasionReport.recordedPayments'.tr();
  static String get overview => 'OccasionReport.overview'.tr();
  static String get snapshot => 'OccasionReport.snapshot'.tr();

  static String get type => 'OccasionReport.type'.tr();
  static String get product => 'OccasionReport.product'.tr();
  static String get count => 'OccasionReport.count'.tr();
  static String get refresh => 'OccasionReport.refresh'.tr();
  static String get text => 'OccasionReport.text'.tr();
  static String get graphic => 'OccasionReport.graphic'.tr();
  static String get export => 'OccasionReport.export'.tr();
  static String get close => 'OccasionReport.close'.tr();
  static String get error => 'OccasionReport.error'.tr();
  static String get exportError => 'OccasionReport.exportError'.tr();
  static String get orders =>
      hasTickets ? 'OccasionReport.orders'.tr() : OrdersStrings.applications;
  static String get tickets => 'OccasionReport.tickets'.tr();
  static String get spots => 'OccasionReport.spots'.tr();
  static String get free => 'OccasionReport.free'.tr();
  static String get products => 'OccasionReport.products'.tr();
  static String get noType => 'OccasionReport.noType'.tr();
  static String get empty => 'OccasionReport.empty'.tr();
  static String get details => 'OccasionReport.details'.tr();
  static String get statesHelp =>
      'OccasionReport.statesHelp'.tr(namedArgs: {'paid': state('paid')});
  static String get spotsHelp => 'OccasionReport.spotsHelp'.tr();
  static String get moneyHelp => 'OccasionReport.moneyHelp'.tr();
  static String get moneyDetails => 'OccasionReport.moneyDetails'.tr();
  static String get productsHelp =>
      'OccasionReport.productsHelp'.tr(namedArgs: {
        'paid': state('paid'),
        'sent': state('sent'),
        'used': state('used'),
      });
  static String get received => 'OccasionReport.received'.tr();
  static String get returned => 'OccasionReport.returned'.tr();
  static String metric(String key) => 'OccasionReport.$key'.tr();
}
