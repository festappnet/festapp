import 'package:flutter/material.dart';
import '../ticket_delivery_strings.dart';
import '../../features/ticket_feature.dart';
import 'ticket_email_preview.dart';

class TicketDeliveryPreview extends StatefulWidget {
  const TicketDeliveryPreview(
      {super.key,
      required this.revision,
      required this.load,
      required this.mode,
      this.title});
  final Object revision;
  final Future<Map<String, dynamic>> Function() load;
  final TicketDeliveryMode mode;
  final String? title;
  @override
  State<TicketDeliveryPreview> createState() => _TicketDeliveryPreviewState();
}

class _TicketDeliveryPreviewState extends State<TicketDeliveryPreview> {
  int _count = 1;
  int _generation = 0;
  Map<String, dynamic>? _preview;
  bool _failed = false;
  @override
  void initState() {
    super.initState();
    _schedule();
  }

  @override
  void didUpdateWidget(covariant TicketDeliveryPreview oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.revision != widget.revision) _schedule();
  }

  void _schedule() {
    final generation = ++_generation;
    _preview = null;
    _failed = false;
    _load(generation);
  }

  Future<void> _load(int generation) async {
    try {
      final result = await widget.load();
      if (mounted && generation == _generation) {
        setState(() => _preview = result);
      }
    } catch (_) {
      if (mounted && generation == _generation) {
        setState(() => _failed = true);
      }
    }
  }

  @override
  void dispose() {
    _generation++;
    super.dispose();
  }

  @override
  Widget build(BuildContext context) =>
      Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(TicketDeliveryStrings.text('preview'),
            style: Theme.of(context).textTheme.titleMedium),
        const SizedBox(height: 8),
        Wrap(spacing: 8, children: [
          for (final count in [1, 3])
            ChoiceChip(
                label: Text(TicketDeliveryStrings.text(
                    count == 1 ? 'oneTicket' : 'threeTickets')),
                selected: count == _count,
                onSelected: (_) => setState(() {
                      _count = count;
                    }))
        ]),
        const SizedBox(height: 8),
        if (_preview == null && !_failed) const LinearProgressIndicator(),
        if (_failed) ...[
          Text(TicketDeliveryStrings.text('previewFailed')),
          TextButton(
              onPressed: () => setState(_schedule),
              child: Text(TicketDeliveryStrings.text('retry'))),
        ],
        if (_preview != null)
          TicketEmailPreview(
              preview: TicketEmailPreview.sample({
                ..._preview!,
                if (widget.title != null) 'title': widget.title
              }, widget.mode, _count),
              sampleCount:
                  widget.mode != TicketDeliveryMode.pdfAttachment ? _count : 0),
      ]);
}
