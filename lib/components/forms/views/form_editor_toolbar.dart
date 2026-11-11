import 'package:material_ui/material_ui.dart';

import '../form_strings.dart';

class FormEditorToolbar extends StatelessWidget {
  const FormEditorToolbar({super.key, this.onPreview, this.onPublicPage});
  final VoidCallback? onPreview;
  final VoidCallback? onPublicPage;

  @override
  Widget build(BuildContext context) => Wrap(
    spacing: 8,
    runSpacing: 4,
    children: [
      if (onPreview != null)
        OutlinedButton.icon(
          onPressed: onPreview,
          icon: const Icon(Icons.preview_outlined),
          label: Text(FormStrings.formPreview),
        ),
      if (onPublicPage != null)
        TextButton.icon(
          onPressed: onPublicPage,
          icon: const Icon(Icons.open_in_new),
          label: Text(FormStrings.publicPage),
        ),
    ],
  );
}
