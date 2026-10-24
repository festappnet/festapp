import 'product_model.dart';
import 'package:festapp_core/json_values.dart';

const _unchanged = Object();

class ProductTypeModel {
  final int? id;
  final int aggregateVersion;
  final String? title;
  final String? description;
  final String? type;
  final Map<String, dynamic>? data;
  final int? occasion;
  final List<ProductModel>? products;

  ProductTypeModel({
    this.id,
    this.aggregateVersion = 0,
    this.title,
    this.description,
    this.type,
    Map<String, dynamic>? data,
    this.occasion,
    List<ProductModel>? products,
  }) : data = data == null
           ? null
           : freezeJsonValue(data) as Map<String, dynamic>,
       products = products == null ? null : List.unmodifiable(products);

  factory ProductTypeModel.fromJson(Map<String, dynamic> json) {
    return ProductTypeModel(
      aggregateVersion: (json['aggregate_version'] as num?)?.toInt() ?? 0,
      id: json['id'],
      title: json['title'],
      description: json['description'],
      type: json['type'],
      data: json['data'],
      occasion: json['occasion'],
      products: json['products'] != null
          ? List<ProductModel>.from(
              json['products'].map((p) => ProductModel.fromJson(p)),
            )
          : null,
    );
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'title': title,
    'description': description,
    'type': type,
    'data': data,
    'occasion': occasion,
    'products': products?.map((product) => product.toJson()).toList(),
  };

  String toBasicString() => title ?? id.toString();
  ProductTypeModel copyWith({
    Object? title = _unchanged,
    Object? description = _unchanged,
    Object? products = _unchanged,
  }) => ProductTypeModel(
    aggregateVersion: aggregateVersion,
    id: id,
    title: identical(title, _unchanged) ? this.title : title as String?,
    description: identical(description, _unchanged)
        ? this.description
        : description as String?,
    type: type,
    data: data,
    occasion: occasion,
    products: identical(products, _unchanged)
        ? this.products
        : products as List<ProductModel>?,
  );
}
