// feature_service.dart

import 'dart:math';

import 'package:collection/collection.dart';
import 'package:fstapp/app_config.dart';
import 'package:fstapp/data_services/rights_service.dart';

import 'companion_feature.dart';
import 'deposit_feature.dart';
import 'feature.dart';
import 'feature_constants.dart';
import 'form_feature.dart';
import 'import_feature.dart';
import 'map_feature.dart';
import 'schedule_feature.dart';
import 'services_feature.dart';
import 'counseling_feature.dart';
import 'ticket_feature.dart';
import 'workshop_feature.dart';
import 'contract_feature.dart';

class FeatureService {
  /// A static list of feature codes that are only available when [AppConfig.isAppSupported] is true.
  static final List<String> appSupportedFeatures = [
    FeatureConstants.workshops,
    FeatureConstants.map,
    FeatureConstants.songbook,
    FeatureConstants.game,
    FeatureConstants.mySchedule,
    FeatureConstants.userGroups,
    FeatureConstants.entryCode,
    FeatureConstants.timetable,
    FeatureConstants.volunteers,
    FeatureConstants.companions,
    ScheduleFeature.metaSchedule,
    FeatureConstants.import,
    FeatureConstants.globalSearch,
    FeatureConstants.eventFeedback,
    FeatureConstants.programNotifications,
    FeatureConstants.counseling,
    FeatureConstants.cleaning,
    FeatureConstants.reception,
  ];

  /// Checks whether the feature with [featureCode] is enabled.
  /// Expects [features] to be a list of Feature objects.
  static bool isFeatureEnabled(String featureCode, {List<Feature>? features}) {
    if (RightsService.currentOccasion() == null && features == null) {
      return false;
    }
    final featureList = features ?? RightsService.currentOccasion()!.features;
    return featureList
        .any((feature) => feature.code == featureCode && feature.isEnabled);
  }

  static bool isTicketPregenerationEnabled({List<Feature>? features}) {
    final ticket =
        getFeatureDetails(FeatureConstants.ticket, features: features);
    return isFeatureEnabled(FeatureConstants.ticket, features: features) &&
        ticket is TicketFeature &&
        ticket.pregeneratedTickets;
  }

  /// Returns a default list of features.
  static List<Feature> getDefaultFeatures() {
    return [
      // This feature is enabled only when the main app features are NOT supported.
      // We set its default as 'false'. The FormFeature constructor
      // will correctly override this to 'true' if !AppConfig.isAppSupported.
      FormFeature(code: FeatureConstants.form, isEnabled: false),

      // These features are always part of the default configuration,
      // though they may be disabled initially.
      TicketFeature(
        code: FeatureConstants.ticket,
        isEnabled: false,
        ticketLightColor: 'FFFFFF',
        ticketDarkColor: '000000',
        ticketBackground: '',
      ),
      DepositFeature(code: FeatureConstants.deposit, isEnabled: false),
      SimpleFeature(code: FeatureConstants.blueprint, isEnabled: false),

      // These features are only added to the list if the app is supported.
      if (AppConfig.isAppSupported) ...[
        WorkshopsFeature(code: FeatureConstants.workshops, isEnabled: true),
        MapFeature(code: FeatureConstants.map, isEnabled: true),
        SimpleFeature(code: FeatureConstants.songbook, isEnabled: false),
        SimpleFeature(code: FeatureConstants.game, isEnabled: false),
        SimpleFeature(code: FeatureConstants.mySchedule, isEnabled: false),
        ServicesFeature(code: FeatureConstants.services, isEnabled: false),
        SimpleFeature(code: FeatureConstants.userGroups, isEnabled: false),
        SimpleFeature(code: FeatureConstants.entryCode, isEnabled: false),
        SimpleFeature(code: FeatureConstants.timetable, isEnabled: false),
        SimpleFeature(code: FeatureConstants.volunteers, isEnabled: false),
        CompanionsFeature(
            code: FeatureConstants.companions,
            isEnabled: false,
            companionsMax: 1,
            allowUserCreate: true,
            allowAdminAssign: false),
        ScheduleFeature(
            code: ScheduleFeature.metaSchedule,
            isEnabled: true,
            scheduleType: 'basic'),
        ImportFeature(code: FeatureConstants.import, isEnabled: true),
        ContractFeature(code: FeatureConstants.contract, isEnabled: false),
        SimpleFeature(code: FeatureConstants.globalSearch, isEnabled: false),
        SimpleFeature(code: FeatureConstants.eventFeedback, isEnabled: false),
        ProgramNotificationsFeature(),
        CounselingFeature(code: FeatureConstants.counseling, isEnabled: false),
        SimpleFeature(code: FeatureConstants.cleaning, isEnabled: false),
        SimpleFeature(code: FeatureConstants.reception, isEnabled: false),
      ],
    ];
  }

  /// Retrieves a feature based on its [featureCode].
  static Feature? getFeatureDetails(String featureCode,
      {List<Feature>? features}) {
    var featuresList = features ??
        RightsService.currentOccasion()?.features ??
        RightsService.currentUnit()?.features;
    if (featuresList == null) {
      return null;
    }
    return featuresList
        .firstWhereOrNull((feature) => feature.code == featureCode);
  }

  static dynamic getDefaultLocation() {
    final mapFeature = getFeatureDetails(FeatureConstants.map);
    if (mapFeature is MapFeature) {
      return {
        "lat": mapFeature.defaultMapLocation.lat,
        "lng": mapFeature.defaultMapLocation.lng
      };
    }
    return {
      "lat": MapFeature.defaultLocation.lat,
      "lng": MapFeature.defaultLocation.lng
    };
  }

  /// Returns true if deposit payment option should be offered to the customer.
  /// False when deposit is disabled, in virtual mode (no payment),
  /// or when the deposit deadline has already passed.
  static bool isDepositChoiceAvailable() {
    if (!isFeatureEnabled(FeatureConstants.deposit)) return false;
    final feature = getFeatureDetails(FeatureConstants.deposit);
    if (feature is! DepositFeature) return false;
    if (feature.isVirtualMode) return false;

    // On-site deadline: always available
    if (feature.depositDeadline == "on_site") return true;

    // Days-before deadline: check if we're still before the cutoff
    final eventStart = RightsService.currentOccasion()?.startTime;
    if (eventStart == null) return false;
    final days = feature.depositDeadlineDays;
    if (days == null) return false;
    final cutoff = eventStart.subtract(Duration(days: days));
    return DateTime.now().isBefore(cutoff);
  }

  /// Returns deposit deadline info: "on_site" or the number of days, or null.
  static DepositFeature? getDepositFeature() {
    final feature = getFeatureDetails(FeatureConstants.deposit);
    return feature is DepositFeature ? feature : null;
  }

  /// True when DepositFeature is enabled and configured in virtual (visual-only) mode.
  static bool isDepositVirtualMode() {
    if (!isFeatureEnabled(FeatureConstants.deposit)) return false;
    return getDepositFeature()?.isVirtualMode ?? false;
  }

  /// Returns the configured global meta-surcharge description (visual-only),
  /// or null when DepositFeature is off, in real mode, or description is empty.
  static String? getMetaSurchargeDescription() {
    if (!isDepositVirtualMode()) return null;
    final desc = getDepositFeature()?.metaSurchargeDescription;
    return (desc != null && desc.trim().isNotEmpty) ? desc : null;
  }

  /// Returns the [ServicesFeature] (Inventory / "Pobyt") config, or null when
  /// the feature is absent or stored as a plain feature.
  static ServicesFeature? getServicesFeature() {
    final feature = getFeatureDetails(FeatureConstants.services);
    return feature is ServicesFeature ? feature : null;
  }

  /// True when the services feature is enabled AND accommodation is permitted
  /// by its mode/sub-toggle. Falls back to the plain enabled flag when the
  /// feature predates the mode config.
  static bool isServiceAccommodationEnabled() =>
      isFeatureEnabled(FeatureConstants.services) &&
      (getServicesFeature()?.allowsAccommodation ?? true);

  /// True when the services feature is enabled AND food/diet is permitted.
  static bool isServiceFoodEnabled() =>
      isFeatureEnabled(FeatureConstants.services) &&
      (getServicesFeature()?.allowsFood ?? true);

  /// Returns the [CounselingFeature] config, or null when the feature is absent
  /// or stored as a plain feature.
  static CounselingFeature? getCounselingFeature({List<Feature>? features}) {
    final feature =
        getFeatureDetails(FeatureConstants.counseling, features: features);
    return feature is CounselingFeature ? feature : null;
  }

  /// True when the counseling feature is enabled. Speakers are core and never
  /// gated; only the counseling flow depends on this (decision R4).
  static bool isCounselingEnabled({List<Feature>? features}) =>
      isFeatureEnabled(FeatureConstants.counseling, features: features);

  /// Returns the maximum number of companions allowed.
  static CompanionsFeature? getCompanionsFeature({List<Feature>? features}) {
    final feature =
        getFeatureDetails(FeatureConstants.companions, features: features);
    return feature is CompanionsFeature ? feature : null;
  }

  static bool isCompanionsEnabled({List<Feature>? features}) =>
      isFeatureEnabled(FeatureConstants.companions, features: features);

  /// The feature is deliberately unavailable until notification delivery is
  /// implemented. Keep this hard gate even if stored configuration says true.
  static bool isProgramNotificationsEnabled({List<Feature>? features}) => false;

  static bool allowsUserCompanionCreation({List<Feature>? features}) =>
      isCompanionsEnabled(features: features) &&
      (getCompanionsFeature(features: features)?.allowUserCreate ?? true);

  static bool allowsAdminCompanionAssignment({List<Feature>? features}) =>
      isCompanionsEnabled(features: features) &&
      (getCompanionsFeature(features: features)?.allowAdminAssign ?? false);

  static int getMaxCompanions({List<Feature>? features}) =>
      max(1, getCompanionsFeature(features: features)?.companionsMax ?? 1);
}
