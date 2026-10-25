import 'package:material_ui/material_ui.dart';
import '../models/ticket_batch_document_part.dart';

/// One compact download menu for the two complete-batch export formats.
class TicketBatchPrintDownloads extends StatelessWidget {
  const TicketBatchPrintDownloads(
      {super.key,
      required this.parts,
      required this.label,
      required this.a4Label,
      required this.zipLabel,
      required this.onSelected,
      this.enabled = true});
  final List<TicketBatchDocumentPart> parts;
  final String label, a4Label, zipLabel;
  final ValueChanged<String> onSelected;
  final bool enabled;
  @override
  Widget build(BuildContext context) {
    final singles = parts.where((p) => p.kind == 'single').toList();
    if (singles.isEmpty || singles.any((p) => p.state != 'ready')) {
      return const SizedBox.shrink();
    }
    return MenuAnchor(
      menuChildren: [
        MenuItemButton(
            onPressed: enabled ? () => onSelected('a4') : null,
            child: Text(a4Label)),
        MenuItemButton(
            onPressed: enabled ? () => onSelected('zip') : null,
            child: Text(zipLabel)),
      ],
      builder: (context, controller, child) => OutlinedButton.icon(
        onPressed: enabled
            ? () => controller.isOpen ? controller.close() : controller.open()
            : null,
        icon: const Icon(Icons.download_outlined, size: 20),
        label: Row(mainAxisSize: MainAxisSize.min, children: [
          Text(label),
          const SizedBox(width: 4),
          const Icon(Icons.expand_more, size: 18),
        ]),
      ),
    );
  }
}
