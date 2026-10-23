import 'dart:async';
import 'package:flutter/material.dart';
import '../ticket_delivery_strings.dart';
import '../../../widgets/app_dialog.dart';
import 'ticket_email_preview.dart';

class TicketDeliveryPreview extends StatefulWidget {
  const TicketDeliveryPreview(
      {super.key, required this.revision, required this.load});
  final Object revision;
  final Future<Map<String, dynamic>> Function(int count) load;
  @override
  State<TicketDeliveryPreview> createState() => _TicketDeliveryPreviewState();
}

class _TicketDeliveryPreviewState extends State<TicketDeliveryPreview> {
  late final _current = ValueNotifier<TicketDeliveryPreview>(widget);

  @override
  void didUpdateWidget(covariant TicketDeliveryPreview oldWidget) {
    super.didUpdateWidget(oldWidget);
    // A preview already open must follow authoring/context changes as well.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _current.value = widget;
    });
  }

  @override
  void dispose() {
    _current.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Align(
      alignment: AlignmentDirectional.centerStart,
      child: TextButton.icon(
          icon: const Icon(Icons.preview_outlined, size: 20),
          label: Text(TicketDeliveryStrings.text('preview')),
          onPressed: () => showDialog<void>(
              context: context,
              builder: (context) => AppAlertDialog(
                  onClose: () => Navigator.pop(context),
                  insetPadding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 24),
                  contentPadding: const EdgeInsets.all(16),
                  title: Text(TicketDeliveryStrings.text('preview')),
                  content: SizedBox(
                      width: 480,
                      child: SingleChildScrollView(
                          child: ValueListenableBuilder<TicketDeliveryPreview>(
                              valueListenable: _current,
                              builder: (context, current, _) =>
                                  _TicketDeliveryPreviewContent(
                                      revision: current.revision,
                                      load: current.load))))))));
}

class _TicketDeliveryPreviewContent extends StatefulWidget {
  const _TicketDeliveryPreviewContent(
      {required this.revision, required this.load});
  final Object revision;
  final Future<Map<String, dynamic>> Function(int count) load;

  @override
  State<_TicketDeliveryPreviewContent> createState() =>
      _TicketDeliveryPreviewContentState();
}

class _TicketDeliveryPreviewContentState
    extends State<_TicketDeliveryPreviewContent> {
  int _count = 1;
  int _generation = 0;
  Timer? _timer;
  Map<String, dynamic>? _preview;
  bool _failed = false;
  @override
  void initState() {
    super.initState();
    _schedule();
  }

  @override
  void didUpdateWidget(covariant _TicketDeliveryPreviewContent oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.revision != widget.revision) _schedule();
  }

  void _schedule() {
    _timer?.cancel();
    final generation = ++_generation;
    _preview = null;
    _failed = false;
    _timer = Timer(const Duration(milliseconds: 300), () async {
      try {
        final result = await widget.load(_count);
        if (mounted && generation == _generation)
          setState(() => _preview = result);
      } catch (_) {
        if (mounted && generation == _generation)
          setState(() => _failed = true);
      }
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    _generation++;
    super.dispose();
  }

  @override
  Widget build(BuildContext context) =>
      Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(TicketDeliveryStrings.text('scopeHelp')),
        const SizedBox(height: 12),
        Wrap(spacing: 8, children: [
          for (final count in [1, 3])
            ChoiceChip(
                label: Text(TicketDeliveryStrings.text(
                    count == 1 ? 'oneTicket' : 'threeTickets')),
                selected: count == _count,
                onSelected: (_) => setState(() {
                      _count = count;
                      _schedule();
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
        if (_preview != null) TicketEmailPreview(preview: _preview!),
      ]);
}
