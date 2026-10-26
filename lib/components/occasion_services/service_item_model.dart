class ServiceItemModel {
  String? title;
  final String code;
  int? reference;
  final String? placeTitle;

  ServiceItemModel({
    required this.title,
    required this.code,
    required this.reference,
    this.placeTitle,
  });

  @override
  String toString() {
    return 'ServiceItem(title: $title, code: $code, reference: $reference)';
  }

  factory ServiceItemModel.fromJson(Map<String, dynamic> json) {
    return ServiceItemModel(
      title: json["title"],
      code: json["code"],
      reference: json["reference"],
      placeTitle: json["place_title"],
    );
  }
}
