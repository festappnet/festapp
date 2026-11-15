class OrderDataProductModel {
  final int? id;
  final String? type;

  /// Charged net amount from the sold snapshot.
  final double? price;
  final double? basePrice;
  final double discountAmount;
  final String? title;
  final String? typeTitle;
  final String? spotTitle;
  final String? spotGroupTitle;
  final String? currencyCode;

  OrderDataProductModel({
    this.id,
    this.type,
    this.price,
    this.basePrice,
    this.discountAmount = 0,
    this.title,
    this.typeTitle,
    this.spotTitle,
    this.spotGroupTitle,
    this.currencyCode,
  });

  factory OrderDataProductModel.fromJson(Map<String, dynamic> json) {
    return OrderDataProductModel(
      id: json['id'],
      type: json['type'],
      basePrice: double.tryParse('${json['base_price']}'),
      discountAmount: double.tryParse('${json['discount_amount']}') ?? 0,
      price: json['price'] != null
          ? double.tryParse(json['price'].toString())
          : null,
      title: json['title'],
      typeTitle: json['type_title'],
      spotTitle: json['spot_title'],
      spotGroupTitle: json['spot_group_title'],
      currencyCode: json['currency_code'],
    );
  }

  @override
  String toString() {
    return title ?? "Product #$id";
  }
}
