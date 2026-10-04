import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:file_saver/file_saver.dart';
import '../ticket_layout_strings.dart';

class TicketPdfDocument extends StatelessWidget {
  final Uint8List bytes;
  const TicketPdfDocument({super.key, required this.bytes});
  @override
  Widget build(BuildContext context) => Center(
      child: FilledButton.icon(
          onPressed: () => FileSaver.instance.saveFile(
              name: 'ticket_layout_sample',
              bytes: bytes,
              mimeType: MimeType.pdf),
          icon: const Icon(Icons.download),
          label: Text(TicketLayoutStrings.downloadPdf)));
}
