import 'package:festapp_core/forms.dart';
import 'package:festapp_core/eshop.dart';
import 'package:festapp_core/json_values.dart';

const _unchanged = Object();

class FormFieldDefinition {
  final int? id;
  final String? deleteBlockedReason;
  final bool? deletionAllowed;
  bool get canDelete => id == null || deletionAllowed == true;
  final DateTime? createdAt;
  final DateTime? updatedAt;
  final String? title;
  final String? description;
  final String? type;
  final bool? isRequired;
  final bool? isHidden;
  final bool? isTicketField;
  final int? form;
  final int? order;
  final int? productTypeId;
  final dynamic data;
  final List<FormOptionDefinition> options;
  final ProductTypeModel? productType;

  static const String metaRequired = "required";
  static const String metaHidden = "hidden";
  static const String metaTitle = "title";
  static const String metaDescription = "description";

  FormFieldDefinition({
    this.id,
    this.deleteBlockedReason,
    this.deletionAllowed,
    this.createdAt,
    this.updatedAt,
    this.title,
    this.description,
    this.type,
    this.isRequired,
    this.isHidden,
    this.isTicketField,
    this.form,
    this.order,
    dynamic data,
    this.productTypeId,
    this.productType,
    List<FormOptionDefinition>? options,
  }) : data = freezeJsonValue(data),
       options = List.unmodifiable(options ?? const []);

  factory FormFieldDefinition.fromJson(Map<String, dynamic> json) {
    var type = json['type'];
    var data = json['data'];
    List<FormOptionDefinition> options = [];
    if ((type == FormMetadata.fieldTypeSelectOne ||
            type == FormMetadata.fieldTypeSelectMany) &&
        data is Map) {
      final rawOptions = data[FormMetadata.metaOptions];
      if (rawOptions is List) {
        options = rawOptions
            .whereType<Map>()
            .where((option) => option[FormOptionDefinition.metaValue] is String)
            .map(
              (option) => FormOptionDefinition.fromJson(
                Map<String, dynamic>.from(option),
              ),
            )
            .toList();
      }
    }
    return FormFieldDefinition(
      id: json['id'],
      deleteBlockedReason: json['delete_blocked_reason'],
      deletionAllowed: json['can_delete'],
      createdAt: json['created_at'] != null
          ? DateTime.parse(json['created_at'])
          : null,
      title: json['title'],
      description: json['description'],
      type: type,
      isRequired: json['is_required'],
      isHidden: json['is_hidden'],
      isTicketField: json['is_ticket_field'],
      form: json['form'],
      order: json['order'],
      data: data,
      productTypeId: json['product_type'],
      productType: json['product_type_data'] != null
          ? ProductTypeModel.fromJson(json['product_type_data'])
          : null,
      options: options,
    );
  }

  Map<String, dynamic> toJson() {
    final jsonData = Map<String, dynamic>.from(data ?? {});

    if (type == FormMetadata.fieldTypeSelectOne ||
        type == FormMetadata.fieldTypeSelectMany ||
        options.isNotEmpty) {
      jsonData[FormMetadata.metaOptions] = options.map((option) {
        final optionData = {FormOptionDefinition.metaValue: option.title};
        if (option.description != null &&
            option.description!.trim().isNotEmpty) {
          optionData[FormOptionDefinition.metaDescription] =
              option.description!;
        }
        return optionData;
      }).toList();
    }

    return {
      'id': id,
      'title': title,
      'description': description,
      'type': type,
      'is_required': isRequired,
      'is_hidden': isHidden,
      'is_ticket_field': isTicketField,
      'order': order,
      'data': jsonData.isNotEmpty ? jsonData : null,
      'product_type': productType,
    };
  }

  FormFieldDefinition copyWith({
    Object? id = _unchanged,
    Object? deleteBlockedReason = _unchanged,
    Object? deletionAllowed = _unchanged,
    Object? createdAt = _unchanged,
    Object? updatedAt = _unchanged,
    Object? title = _unchanged,
    Object? description = _unchanged,
    Object? type = _unchanged,
    Object? isRequired = _unchanged,
    Object? isHidden = _unchanged,
    Object? isTicketField = _unchanged,
    Object? form = _unchanged,
    Object? order = _unchanged,
    Object? productTypeId = _unchanged,
    Object? data = _unchanged,
    Object? options = _unchanged,
    Object? productType = _unchanged,
  }) => FormFieldDefinition(
    id: identical(id, _unchanged) ? this.id : id as int?,
    deleteBlockedReason: identical(deleteBlockedReason, _unchanged)
        ? this.deleteBlockedReason
        : deleteBlockedReason as String?,
    deletionAllowed: identical(deletionAllowed, _unchanged)
        ? this.deletionAllowed
        : deletionAllowed as bool?,
    createdAt: identical(createdAt, _unchanged)
        ? this.createdAt
        : createdAt as DateTime?,
    updatedAt: identical(updatedAt, _unchanged)
        ? this.updatedAt
        : updatedAt as DateTime?,
    title: identical(title, _unchanged) ? this.title : title as String?,
    description: identical(description, _unchanged)
        ? this.description
        : description as String?,
    type: identical(type, _unchanged) ? this.type : type as String?,
    isRequired: identical(isRequired, _unchanged)
        ? this.isRequired
        : isRequired as bool?,
    isHidden: identical(isHidden, _unchanged)
        ? this.isHidden
        : isHidden as bool?,
    isTicketField: identical(isTicketField, _unchanged)
        ? this.isTicketField
        : isTicketField as bool?,
    form: identical(form, _unchanged) ? this.form : form as int?,
    order: identical(order, _unchanged) ? this.order : order as int?,
    productTypeId: identical(productTypeId, _unchanged)
        ? this.productTypeId
        : productTypeId as int?,
    data: identical(data, _unchanged) ? this.data : data as dynamic,
    options: identical(options, _unchanged)
        ? this.options
        : options as List<FormOptionDefinition>,
    productType: identical(productType, _unchanged)
        ? this.productType
        : productType as ProductTypeModel?,
  );
}
