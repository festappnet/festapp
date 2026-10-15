import 'package:festapp_core/program.dart';
import 'package:festapp_core/map.dart';
import 'package:fstapp/components/timeline/schedule_helper.dart';

class CompanionModel {
  final String id;
  final String name;
  final String surname;
  final String groupTitle;
  final Map<String, dynamic> occasionServices;
  PlaceModel? accommodationPlace;
  final String origin;
  final bool canOwnerDelete;
  List<int> eventIds;
  List<EventModel>? schedule = [];
  List<TimeBlockItem> timeBlocks = [];

  CompanionModel({
    required this.id,
    required this.name,
    this.surname = '',
    this.groupTitle = '',
    this.occasionServices = const {},
    this.accommodationPlace,
    this.origin = 'self_created',
    bool? canOwnerDelete,
    required this.eventIds,
  }) : canOwnerDelete = canOwnerDelete ?? origin == 'self_created';

  String get fullName =>
      [name, surname].where((part) => part.trim().isNotEmpty).join(' ');

  factory CompanionModel.fromJson(Map<String, dynamic> json) {
    return CompanionModel(
        id: json["id"],
        name: json["name"],
        surname: json["surname"] ?? '',
        groupTitle: json["group_title"] ?? '',
        occasionServices: json["services"] is Map
            ? Map<String, dynamic>.from(json["services"] as Map)
            : const {},
        accommodationPlace: json["accommodation_place"] is Map
            ? PlaceModel.fromJson(
                Map<String, dynamic>.from(json["accommodation_place"] as Map))
            : null,
        origin: json["origin"] ?? 'self_created',
        canOwnerDelete: json["can_owner_delete"],
        eventIds:
            json["event_ids"] != null ? List<int>.from(json["event_ids"]) : []);
  }

  Map<String, dynamic> toJson() => {
        "id": id,
        "name": name,
        "surname": surname,
        "group_title": groupTitle,
        "services": occasionServices,
        "accommodation_place": accommodationPlace?.toJson(),
        "origin": origin,
        "can_owner_delete": canOwnerDelete,
        "event_ids": eventIds,
      };

  bool isSignedIn(int event) => eventIds.any((e) => e == event);
}
