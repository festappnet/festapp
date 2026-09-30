import 'package:flutter/material.dart';
import 'package:fstapp/components/_shared/common_strings.dart';
import 'package:fstapp/components/forms/models/form_option_model.dart';
import 'package:fstapp/widgets/standard_dialog.dart';
import 'package:fstapp/components/html/rich_html_editor_controller.dart';
import 'package:fstapp/components/html/editable_html_field.dart';

class OptionDetailEditorDialog extends StatefulWidget {
  final FormOptionModel option;
  final int? occasionId;
  final HtmlSaveCoordinator? coordinator;

  const OptionDetailEditorDialog(
      {super.key, required this.option, this.occasionId, this.coordinator});

  @override
  _OptionDetailEditorDialogState createState() =>
      _OptionDetailEditorDialogState();
}

class _OptionDetailEditorDialogState extends State<OptionDetailEditorDialog> {
  late String _description;

  @override
  void initState() {
    super.initState();
    _description = widget.option.description ?? "";
  }

  @override
  Widget build(BuildContext context) {
    return StandardDialog(
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const SizedBox(height: 32),
            Text(
              CommonStrings.description,
              style: Theme.of(context)
                  .textTheme
                  .titleLarge
                  ?.copyWith(fontWeight: FontWeight.w600),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 8),
            EditableHtmlField(html: _description, coordinator: widget.coordinator,
              owner: HtmlMediaOwner.occasion(widget.occasionId),
              onChanged: (html) => setState(() { _description = html; widget.option.description = html; })),
            const SizedBox(height: 24),
          ],
        ),
      ),
    );
  }
}
