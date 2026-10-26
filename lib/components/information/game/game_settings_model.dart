import 'package:fstapp/database_tables/tb.dart';

class GameSettingsModel {
  DateTime? start;
  DateTime? end;

  GameSettingsModel({this.start, this.end});

  factory GameSettingsModel.fromJson(Map<String, dynamic> json) {
    return GameSettingsModel(
      start: json[Tb.occasions.data_game_start] != null
          ? DateTime.parse(json[Tb.occasions.data_game_start])
          : null,
      end: json[Tb.occasions.data_game_end] != null
          ? DateTime.parse(json[Tb.occasions.data_game_end])
          : null,
    );
  }

  Map<String, dynamic> toJson() => {
        Tb.occasions.data_game_start: start?.toIso8601String(),
        Tb.occasions.data_game_end: end?.toIso8601String(),
      };
}
