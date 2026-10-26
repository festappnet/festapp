import 'package:fstapp/database_tables/tb.dart';

class ResourceSlotModel {
  int? id;
  String? title;
  int resourceId;

  ResourceSlotModel({
    this.id,
    this.title,
    required this.resourceId,
  });

  factory ResourceSlotModel.fromJson(Map<String, dynamic> json) {
    final t = Tb.resource_slots;
    return ResourceSlotModel(
      id: json[t.id],
      title: json[t.title],
      resourceId: json[t.resource],
    );
  }

  Map<String, dynamic> toJson() {
    final t = Tb.resource_slots;
    return {
      t.id: id,
      t.title: title,
      t.resource: resourceId,
    };
  }
}
