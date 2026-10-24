import 'package:flutter/material.dart';
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
    return PopupMenuButton<String>(
        enabled: enabled,
        tooltip: label,
        onSelected: onSelected,
        itemBuilder: (_) => [
              PopupMenuItem(value: 'a4', child: Text(a4Label)),
              PopupMenuItem(value: 'zip', child: Text(zipLabel))
            ],
        child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            child: Row(mainAxisSize: MainAxisSize.min, children: [
              const Icon(Icons.download_outlined, size: 20),
              const SizedBox(width: 8),
              Text(label)
            ])));
  }
}
