import 'package:material_ui/material_ui.dart';
import 'package:fstapp/components/html/html_view.dart';

class FormMessageWidget extends StatelessWidget {
  final String message;
  final String defaultMessage;
  final bool isEditable;
  final VoidCallback? onEdit;

  const FormMessageWidget({
    super.key,
    required this.message,
    required this.defaultMessage,
    this.isEditable = false,
    this.onEdit,
  });

  @override
  Widget build(BuildContext context) {
    final displayedMessage = message.isNotEmpty ? message : defaultMessage;
    final htmlContainer = Container(
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        border: Border.all(color: Colors.grey),
        borderRadius: BorderRadius.circular(4),
      ),
      child: HtmlView(
        fontSize: 14,
        html: displayedMessage,
        isSelectable: true,
      ),
    );

    if (!isEditable) {
      return Padding(
        padding: const EdgeInsets.only(top: 8),
        child: htmlContainer,
      );
    } else {
      return Padding(
        padding: const EdgeInsets.only(top: 8),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(child: htmlContainer),
            IconButton(
              icon: const Icon(Icons.edit),
              onPressed: onEdit,
            ),
          ],
        ),
      );
    }
  }
}
