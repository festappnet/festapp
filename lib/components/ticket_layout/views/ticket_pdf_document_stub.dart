import 'dart:typed_data';
import 'package:flutter/material.dart';
import '../ticket_layout_strings.dart';

class TicketPdfDocument extends StatelessWidget {
  final Uint8List bytes;
  const TicketPdfDocument({super.key, required this.bytes});
  @override
  Widget build(BuildContext context) =>
      Center(child: Text(TicketLayoutStrings.downloadPdf));
}
