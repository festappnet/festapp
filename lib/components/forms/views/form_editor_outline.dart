import 'package:material_ui/material_ui.dart';

import '../form_strings.dart';
import '../models/form_field_draft.dart';
import '../widgets_editor/form_fields_navigation_controller.dart';

class FormEditorOutline extends StatelessWidget {
  const FormEditorOutline({
    super.key,
    required this.fields,
    required this.selectedIdentity,
    required this.selectedSection,
    required this.onAvailability,
    required this.onIntroduction,
    required this.onField,
  });
  final List<FormFieldNavigationItem> fields;
  final Object? selectedIdentity;
  final String? selectedSection;
  final VoidCallback onAvailability;
  final VoidCallback onIntroduction;
  final ValueChanged<FormFieldDraft> onField;

  @override
  Widget build(BuildContext context) => ListView(
    primary: false,
    padding: const EdgeInsets.symmetric(vertical: 12),
    children: [
      Padding(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
        child: Text(
          FormStrings.formOutline,
          style: Theme.of(context).textTheme.titleSmall,
        ),
      ),
      ListTile(
        selected: selectedIdentity == null && selectedSection == 'availability',
        title: Text(FormStrings.availability),
        onTap: onAvailability,
      ),
      ListTile(
        selected: selectedIdentity == null && selectedSection == 'introduction',
        title: Text(FormStrings.formIntroduction),
        onTap: onIntroduction,
      ),
      const Divider(),
      for (final item in fields)
        ListTile(
          key: ValueKey(item.identity),
          selected: selectedIdentity == item.identity,
          title: Text(item.title),
          onTap: () => onField(item.field),
        ),
    ],
  );
}
