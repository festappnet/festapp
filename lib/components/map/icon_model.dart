import 'package:fstapp/database_tables/tb.dart';

class IconModel {
  static const String missingLabel = '---';

  int? id;
  String? data;
  String? link;
  int? unit;
  int? organization;
  String? createdBy;

  static String iconsOffline = Tb.icons.table;

  /// Legacy icons (no owning unit) are read-only and cannot be deleted.
  bool get isLegacy => unit == null;

  /// The only SVG payload that presentation code may render.
  ///
  /// Historical rows may legitimately have nullable or incomplete data even
  /// though newly uploaded icons are validated before insertion.
  String? get renderableSvgData {
    final svg = data?.trim();
    return svg != null && svg.isNotEmpty && svg.contains('<svg') ? svg : null;
  }

  String? get normalizedLink {
    final label = link?.trim();
    return label == null || label.isEmpty ? null : label;
  }

  String get displayLabel => normalizedLink ?? missingLabel;

  factory IconModel.fromJson(Map<String, dynamic> json) {
    return IconModel(
      link: json[Tb.icons.link],
      data: json[Tb.icons.data],
      id: json[Tb.icons.id],
      unit: json[Tb.icons.unit],
      organization: json[Tb.icons.organization],
      createdBy: json[Tb.icons.created_by],
    );
  }

  Map toJson() => {Tb.icons.link: link, Tb.icons.data: data, Tb.icons.id: id};

  IconModel(
      {this.link,
      this.data,
      this.id,
      this.unit,
      this.organization,
      this.createdBy});

  @override
  String toString() {
    return displayLabel;
  }
}
