import 'dart:convert';
import 'package:flutter/material.dart';
import '../models/ticket_layout.dart';
import '../ticket_layout_controller.dart';
import '../ticket_layout_service.dart';
import '../ticket_layout_strings.dart';
import 'ticket_layout_canvas.dart';

/// Uses the same renderer and templates as the full ticket editor.
class TicketTemplateGallery extends StatefulWidget {
  final TicketLayoutResources resources;
  final TicketTemplate? selected;
  final ValueChanged<String> onSelected;
  const TicketTemplateGallery(
      {super.key,
      required this.resources,
      required this.selected,
      required this.onSelected});

  @override
  State<TicketTemplateGallery> createState() => _TicketTemplateGalleryState();
}

class _TicketTemplateGalleryState extends State<TicketTemplateGallery> {
  late Map<String, TicketLayoutController> _previews;

  void _load() {
    final presets = widget.resources.presets;
    _previews = (presets.isEmpty
            ? {'classic': widget.resources.preset}
            : presets)
        .map((key, template) =>
            MapEntry(key, TicketLayoutController(template, artworkKey: key)));
  }

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void didUpdateWidget(covariant TicketTemplateGallery oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.resources != widget.resources) {
      for (final c in _previews.values) {
        c.dispose();
      }
      _load();
    }
  }

  @override
  void dispose() {
    for (final c in _previews.values) {
      c.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) =>
      LayoutBuilder(builder: (context, bounds) {
        final columns = bounds.maxWidth < 600
            ? 1
            : bounds.maxWidth < 1000
                ? 2
                : 3;
        final width = (bounds.maxWidth - (columns - 1) * 12) / columns;
        final selected = widget.selected == null
            ? null
            : jsonEncode(widget.selected!.toJson());
        return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(TicketLayoutStrings.styles,
              style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 12),
          Wrap(spacing: 12, runSpacing: 12, children: [
            for (final entry in _previews.entries)
              SizedBox(
                  width: width,
                  height: 240,
                  child: Builder(builder: (context) {
                    final active =
                        selected == jsonEncode(entry.value.document.toJson());
                    final label =
                        TicketLayoutStrings.binding('style_${entry.key}');
                    return Semantics(
                        selected: active,
                        child: Card(
                          margin: EdgeInsets.zero,
                          clipBehavior: Clip.antiAlias,
                          shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12),
                              side: BorderSide(
                                  width: active ? 2 : 1,
                                  color: active
                                      ? Theme.of(context).colorScheme.primary
                                      : Theme.of(context).dividerColor)),
                          child: InkWell(
                              key: ValueKey('ticket-template-${entry.key}'),
                              onTap: () => widget.onSelected(entry.key),
                              child: Column(children: [
                                Expanded(
                                    child: Padding(
                                        padding: const EdgeInsets.all(16),
                                        child: FittedBox(
                                            child: CustomPaint(
                                                size: entry
                                                    .value.document.area.size,
                                                painter: TicketLayoutPainter(
                                                    entry.value,
                                                    widget.resources,
                                                    widget.resources
                                                        .previewData(
                                                            entry
                                                                .value.document,
                                                            'normal'),
                                                    cropToTicket: true))))),
                                Padding(
                                    padding: const EdgeInsets.all(12),
                                    child: Row(children: [
                                      Icon(active
                                          ? Icons.radio_button_checked
                                          : Icons.radio_button_unchecked),
                                      const SizedBox(width: 8),
                                      Expanded(child: Text(label)),
                                    ])),
                              ])),
                        ));
                  })),
          ]),
        ]);
      });
}
