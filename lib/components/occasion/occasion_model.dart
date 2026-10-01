import 'package:fstapp/components/features/ticket_feature.dart';
import 'package:collection/collection.dart';
import 'package:fstapp/components/features/feature.dart';
import 'package:fstapp/components/forms/models/form_model.dart';
import 'package:fstapp/components/occasion_services/service_item_model.dart';
import 'package:fstapp/database_tables/tb.dart';
import 'package:fstapp/services/time_helper.dart';

/// Represents the statistics for an occasion.
class StatsModel {
  final int total;
  final int paidOrSent;
  final int used;
  final int ordered;
  final int storno;
  final int users;

  StatsModel({
    this.total = 0,
    this.paidOrSent = 0,
    this.used = 0,
    this.ordered = 0,
    this.storno = 0,
    this.users = 0,
  });

  /// A helper getter to easily check if all stats are zero.
  bool get areAllZero =>
      total == 0 &&
      paidOrSent == 0 &&
      used == 0 &&
      ordered == 0 &&
      storno == 0 &&
      users == 0;

  factory StatsModel.fromJson(Map<String, dynamic> json) {
    return StatsModel(
      total: json['total'] ?? 0,
      paidOrSent: json['paid_or_sent'] ?? 0,
      used: json['used'] ?? 0,
      ordered: json['ordered'] ?? 0,
      storno: json['storno'] ?? 0,
      users: json['users'] ?? 0,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'total': total,
      'paid_or_sent': paidOrSent,
      'used': used,
      'ordered': ordered,
      'storno': storno,
      'users': users,
    };
  }
}

class OccasionModel {
  static const String occasionsOffline = "occasionsOffline";

  int? id;
  DateTime? createdAt;
  DateTime? updatedAt;
  DateTime? startTime;
  DateTime? endTime;
  bool isOpen;
  bool isHidden;
  bool isPromoted;
  bool hasOrders;
  String? link;
  String? title;
  String? description;
  Map<String, dynamic>? data;
  Map<String, dynamic>? services;
  int? organization;
  int? unit;
  FormModel? form;
  List<Feature> features;
  StatsModel? stats;
  int aggregateVersion;

  OccasionModel({
    this.id,
    this.createdAt,
    this.updatedAt,
    this.startTime,
    this.endTime,
    required this.isOpen,
    required this.isHidden,
    required this.isPromoted,
    this.hasOrders = false,
    this.link,
    this.title,
    this.description,
    this.data,
    this.services,
    this.organization,
    this.unit,
    this.form,
    List<Feature>? features,
    this.stats,
    this.aggregateVersion = 0,
  }) : features = features ?? [];

  factory OccasionModel.fromJson(Map<String, dynamic> json) {
    Map<String, dynamic> data = json[Tb.occasions.data] ?? {};

    var servicesData = json[Tb.occasions.services];

    return OccasionModel(
      id: json[Tb.occasions.id],
      createdAt: json[Tb.occasions.created_at] != null
          ? DateTime.parse(json[Tb.occasions.created_at])
          : null,
      updatedAt: json[Tb.occasions.updated_at] != null
          ? DateTime.parse(json[Tb.occasions.updated_at])
          : null,
      startTime: json[Tb.occasions.start_time] != null
          ? DateTime.parse(json[Tb.occasions.start_time])
              .toOccasionTime(data[Tb.occasions.data_timezone])
          : null,
      endTime: json[Tb.occasions.end_time] != null
          ? DateTime.parse(json[Tb.occasions.end_time])
              .toOccasionTime(data[Tb.occasions.data_timezone])
          : null,
      isOpen: json[Tb.occasions.is_open] ?? false,
      isHidden: json[Tb.occasions.is_hidden] ?? false,
      isPromoted: json[Tb.occasions.is_promoted] ?? false,
      hasOrders: json['has_orders'] ?? false,
      link: json[Tb.occasions.link],
      title: json[Tb.occasions.title],
      description: json[Tb.occasions.description],
      data: data,

      // Assign the extracted services map to the dedicated field
      services: servicesData is Map<String, dynamic>
          ? servicesData
          : (servicesData is Map
              ? Map<String, dynamic>.from(servicesData)
              : null),

      organization: json[Tb.occasions.organization],
      unit: json[Tb.occasions.unit],
      form: json["form"] != null ? FormModel.fromJson(json["form"]) : null,
      features: json[Tb.occasions.features] is List
          ? List<Feature>.from((json[Tb.occasions.features] as List)
              .map((featureJson) => Feature.fromJson(featureJson)))
          : [],
      stats: json['stats'] != null ? StatsModel.fromJson(json['stats']) : null,
      aggregateVersion: (json['aggregate_version'] as num?)?.toInt() ?? 0,
    );
  }

  Map<String, dynamic> toSaveJson() {
    final result = toJson();
    for (final ticket in features.whereType<TicketFeature>()) {
      if (ticket.layoutChange != null) {
        result['ticket_layout_change'] = ticket.layoutChange;
      }
    }
    return result;
  }

  void markTicketLayoutSaved() {
    for (final ticket in features.whereType<TicketFeature>()) {
      ticket.markLayoutSaved();
    }
  }

  Map<String, dynamic> toJson() {
    return {
      Tb.occasions.id: id,
      Tb.occasions.start_time: startTime
          ?.toUtcFromOccasionTime(data?[Tb.occasions.data_timezone])
          .toIso8601String(),
      Tb.occasions.end_time: endTime
          ?.toUtcFromOccasionTime(data?[Tb.occasions.data_timezone])
          .toIso8601String(),
      Tb.occasions.is_open: isOpen,
      Tb.occasions.is_hidden: isHidden,
      Tb.occasions.is_promoted: isPromoted,
      'has_orders': hasOrders,
      Tb.occasions.link: link,
      Tb.occasions.title: title,
      Tb.occasions.description: description,
      Tb.occasions.data: data,
      Tb.occasions.services: services,
      Tb.occasions.organization: organization,
      Tb.occasions.unit: unit,
      Tb.occasions.features: features,
      'stats': stats,
    };
  }

  /// Gets a reference to a specific service item based on user's data.
  ///
  /// This method now uses the top-level [services] field.
  ServiceItemModel? getReferenceToService(
      String serviceType, Map<String, dynamic>? userServices) {
    // Retrieve the list of services for the specified service type
    // This now uses the 'services' field
    var servs = services?[serviceType] ?? [];

    var serviceRecords = userServices?[serviceType] as Map? ?? {};
    var userCode =
        serviceRecords.keys.firstWhereOrNull((key) => key.isNotEmpty);
    if (userCode == null) {
      return null;
    }
    for (var service in servs) {
      // Ensure service is a Map before accessing "code"
      if (service is Map && service["code"] == userCode) {
        return ServiceItemModel.fromJson(service as Map<String, dynamic>);
      }
    }

    return null;
  }
}
