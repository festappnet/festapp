import 'dart:js_interop';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import '../ticket_layout_strings.dart';
import 'package:web/web.dart' as web;

class TicketPdfDocument extends StatefulWidget {
  final Uint8List bytes;
  const TicketPdfDocument({super.key, required this.bytes});
  @override
  State<TicketPdfDocument> createState() => _TicketPdfDocumentState();
}

class _TicketPdfDocumentState extends State<TicketPdfDocument> {
  late final url = web.URL.createObjectURL(web.Blob(
      [widget.bytes.toJS].toJS, web.BlobPropertyBag(type: 'application/pdf')));
  @override
  void dispose() {
    web.URL.revokeObjectURL(url);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => !web.window.navigator.pdfViewerEnabled
      ? Center(
          child: Padding(
              padding: const EdgeInsets.all(24),
              child: Column(mainAxisSize: MainAxisSize.min, children: [
                Text(TicketLayoutStrings.pdfExternalHint,
                    textAlign: TextAlign.center),
                const SizedBox(height: 16),
                FilledButton.icon(
                    onPressed: () => web.window.open(url, '_blank', 'noopener'),
                    icon: const Icon(Icons.open_in_new),
                    label: Text(TicketLayoutStrings.openPdf)),
              ])))
      : HtmlElementView.fromTagName(
          tagName: 'iframe',
          onElementCreated: (element) {
            final frame = element as web.HTMLIFrameElement;
            frame.src = url;
            frame.title = 'PDF';
            frame.style
              ..width = '100%'
              ..height = '100%'
              ..border = '0';
          });
}
