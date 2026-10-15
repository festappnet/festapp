import 'package:festapp_core/forms.dart';

const _unchanged = Object();

class FormOptionDefinition {
  static const String metaValue = "value";
  static const String metaDescription = "description";

  static const String metaOptionsId = "id";
  static const String metaOptionsName = "name";
  static const String metaOptionsPrice = "price";

  final String type;
  final String title;
  final String? description;
  final String id;

  FormOptionDefinition(
    this.id,
    this.title, {
    this.type = FormMetadata.fieldTypeSelectOne,
    this.description,
  });

  FormOptionDefinition copyWith({
    String? title,
    Object? description = _unchanged,
  }) => FormOptionDefinition(
    id,
    title ?? this.title,
    type: type,
    description: identical(description, _unchanged)
        ? this.description
        : description as String?,
  );

  @override
  String toString() => title;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is FormOptionDefinition &&
          runtimeType == other.runtimeType &&
          id == other.id;

  @override
  int get hashCode => id.hashCode;

  factory FormOptionDefinition.fromJson(Map<String, dynamic> json) {
    return FormOptionDefinition(
      json[metaValue]!,
      json[metaValue]!,
      description: json[metaDescription],
    );
  }

  dynamic toJson() {
    if (type == FormMetadata.fieldTypeSelectOne) {
      return title;
    }
    return id;
  }
}
