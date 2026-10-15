import 'package:festapp_core/forms.dart';

class FormOptionDraft {
  final String type;
  String title;
  String? description;
  final String id;

  FormOptionDraft(this.id, this.title,
      {this.type = FormMetadata.fieldTypeSelectOne, this.description});

  @override
  String toString() => title;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is FormOptionDraft &&
          runtimeType == other.runtimeType &&
          id == other.id;

  @override
  int get hashCode => id.hashCode;

  FormOptionDraft.fromDefinition(FormOptionDefinition option)
      : id = option.id,
        title = option.title,
        description = option.description,
        type = option.type;
  factory FormOptionDraft.fromJson(Map<String, dynamic> json) =>
      FormOptionDraft.fromDefinition(FormOptionDefinition.fromJson(json));
  FormOptionDefinition freeze() =>
      FormOptionDefinition(id, title, type: type, description: description);
  dynamic toJson() => freeze().toJson();
}
