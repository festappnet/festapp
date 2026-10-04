import 'package:flutter/material.dart';
import 'package:fstapp/components/_shared/common_strings.dart';
import 'package:fstapp/components/html/editable_html_field.dart';
import 'package:fstapp/components/html/rich_html_editor_controller.dart';

class DescriptionWithEdit extends StatelessWidget {
  const DescriptionWithEdit({super.key, required this.description,
    this.defaultDescription, required this.onDescriptionChanged, required this.occasionId});
  final String description;
  final String? defaultDescription;
  final int occasionId;
  final ValueChanged<String> onDescriptionChanged;
  @override Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(top: 8),
    child: EditableHtmlField(html: description == (defaultDescription ?? CommonStrings.description) ? '' : description,
      placeholder: defaultDescription ?? CommonStrings.description, fontSize: 14, owner: HtmlMediaOwner.occasion(occasionId),
      onChanged: onDescriptionChanged));
}
