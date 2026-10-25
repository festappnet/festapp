import 'package:collection/collection.dart';
import 'package:fstapp/components/features/feature.dart';
import 'package:fstapp/components/occasion/occasion_model.dart';
import 'package:fstapp/components/occasion_services/service_item_model.dart';
import 'package:fstapp/database_tables/tb.dart';

class OccasionSettingsModel {
  DateTime? eventStartTime;
  DateTime? eventEndTime;
  Map<String, dynamic>? services;
  Map<String, dynamic>? data;

  // Game fields
  DateTime? gameStartTime;
  DateTime? gameEndTime;

  // Features
  List<Feature>? features;

  // Visibility switch
  bool? isHidden;

  static const String globalSettingsOffline = "globalSettingsOffline";

  OccasionSettingsModel({
    this.eventStartTime,
    this.eventEndTime,
    this.services,
    this.gameStartTime,
    this.gameEndTime,
    this.features,
    this.data,
    this.isHidden,
  });

  /// Creates an [OccasionSettingsModel] from an [OccasionModel].
  ///
  /// This factory constructor maps the properties from an existing [OccasionModel]
  /// instance to a new [OccasionSettingsModel] instance.
  factory OccasionSettingsModel.fromOccasion(OccasionModel occasion) {
    final dataPart = occasion.data ?? <String, dynamic>{};
    final servicesPart =
        dataPart[Tb.occasions.services] as Map<String, dynamic>?;
    final gameSettings =
        dataPart[Tb.occasions.data_game] as Map<String, dynamic>? ??
        <String, dynamic>{};

    final gameStartString =
        gameSettings[Tb.occasions.data_game_start] as String?;
    final gameEndString = gameSettings[Tb.occasions.data_game_end] as String?;

    return OccasionSettingsModel(
      eventStartTime: occasion.startTime,
      eventEndTime: occasion.endTime,
      services: servicesPart,
      gameStartTime: gameStartString != null
          ? DateTime.tryParse(gameStartString)
          : null,
      gameEndTime: gameEndString != null
          ? DateTime.tryParse(gameEndString)
          : null,
      features: occasion.features,
      data: occasion.data,
      isHidden: occasion.isHidden,
    );
  }

  static OccasionSettingsModel fromJson(Map<String, dynamic> json) {
    // Initialize to default settings if required data is missing
    var servicesPart = json[Tb.occasions.services] as Map<String, dynamic>?;
    var featuresPart = json[Tb.occasions.features] as List<dynamic>?;
    var dataPart = json[Tb.occasions.data] as Map<String, dynamic>?;

    if (dataPart == null) {
      var defaultSettings = OccasionSettingsModel.defaultSettings;
      defaultSettings.services = servicesPart;
      return defaultSettings;
    }

    var gameSettings =
        dataPart[Tb.occasions.data_game] as Map<String, dynamic>? ?? {};
    var hiddenFlag = dataPart[Tb.occasions.is_hidden] as bool?;

    return OccasionSettingsModel(
      eventStartTime: json[Tb.occasions.start_time] != null
          ? DateTime.tryParse(json[Tb.occasions.start_time])
          : null,
      eventEndTime: json[Tb.occasions.end_time] != null
          ? DateTime.tryParse(json[Tb.occasions.end_time])
          : null,
      gameStartTime: gameSettings[Tb.occasions.data_game_start] != null
          ? DateTime.tryParse(gameSettings[Tb.occasions.data_game_start])
          : null,
      gameEndTime: gameSettings[Tb.occasions.data_game_end] != null
          ? DateTime.tryParse(gameSettings[Tb.occasions.data_game_end])
          : null,
      services: servicesPart,
      features: featuresPart?.map((f) => Feature.fromJson(f)).toList(),
      data: dataPart,
      isHidden: hiddenFlag,
    );
  }

  Map<String, dynamic> toJson() {
    final existingGame = data?[Tb.occasions.data_game];
    final dataMap = <String, dynamic>{
      ...?data,
      Tb.occasions.data_game: {
        if (existingGame is Map<String, dynamic>) ...existingGame,
        Tb.occasions.data_game_start: gameStartTime?.toIso8601String(),
        Tb.occasions.data_game_end: gameEndTime?.toIso8601String(),
      },
    };

    return {
      Tb.occasions.services: services,
      Tb.occasions.features: features?.map((f) => f.toJson()).toList(),
      Tb.occasions.is_hidden: isHidden,
      Tb.occasions.data: dataMap,
    };
  }

  static OccasionSettingsModel defaultSettings = OccasionSettingsModel();

  ServiceItemModel? getReferenceToService(
    String serviceType,
    Map<String, dynamic>? userServices,
  ) {
    // Retrieve the list of services for the specified service type
    var servs = services?[serviceType] ?? [];

    var serviceRecords = userServices?[serviceType] as Map? ?? {};
    var userCode = serviceRecords.keys.firstWhereOrNull(
      (key) => key.isNotEmpty,
    );
    if (userCode == null) {
      return null;
    }
    for (var service in servs) {
      if (service["code"] == userCode) {
        return ServiceItemModel.fromJson(service);
      }
    }

    return null;
  }
}
