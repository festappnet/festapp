class OrderDataProductModel {
  final int? id;
  final String? type;
  final double? price;
  final String? title;
  final String? typeTitle;
  final String? spotTitle;
  final String? currencyCode;

  OrderDataProductModel({
    this.id,
    this.type,
    this.price,
    this.title,
    this.typeTitle,
    this.spotTitle,
    this.currencyCode,
  });

  factory OrderDataProductModel.fromJson(Map<String, dynamic> json) {
    return OrderDataProductModel(
      id: json['id'],
      type: json['type'],
      price: json['price'] != null
          ? double.tryParse(json['price'].toString())
          : null,
      title: json['title'],
      typeTitle: json['type_title'],
      spotTitle: json['spot_title'],
      currencyCode: json['currency_code'],
    );
  }

  @override
  String toString() {
    return title ?? "Product #$id";
  }
}
