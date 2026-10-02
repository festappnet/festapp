import 'package:flutter/material.dart';
import 'package:fstapp/components/features/ticket_feature.dart';
import 'package:fstapp/components/features/features_strings.dart';
import 'package:fstapp/data_services/rights_service.dart';
import 'package:fstapp/services/exception_handler.dart';
import '../models/ticket_layout.dart';
import '../ticket_layout_controller.dart';
import '../ticket_layout_service.dart';
import '../ticket_layout_strings.dart';
import 'ticket_layout_editor.dart';
import 'ticket_layout_canvas.dart';

class TicketSettings extends StatefulWidget {
  final TicketFeature feature;
  final int occasionId;
  final TicketLayoutService service;
  TicketSettings(
      {super.key,
      required this.feature,
      required this.occasionId,
      TicketLayoutService? service})
      : service = service ?? TicketLayoutService();
  @override
  State<TicketSettings> createState() => _TicketSettingsState();
}

class _TicketSettingsState extends State<TicketSettings> {
  TicketLayoutService get service => widget.service;
  TicketLayoutResources? thumbnail;
  TicketLayoutController? thumbnailController;
  bool busy = false;
  int generation = 0;
  // Keep the persisted slot for compatibility; visual choices belong to templates.
  String get type => widget.feature.ticketType == 'named' ? 'named' : 'wide';
  bool get unsupported =>
      widget.feature.layout != null &&
      widget.feature.layout!['schemaVersion'] != 1;
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => refresh());
  }

  @override
  void dispose() {
    generation++;
    thumbnail?.dispose();
    thumbnailController?.dispose();
    super.dispose();
  }

  Future<void> refresh() async {
    final request = ++generation;
    if (unsupported) return;
    await ExceptionHandler.guard(context, futureFunction: () async {
      final next = await service.resolve(widget.occasionId, type,
          widget.feature.layout, widget.feature.ticketBackground);
      if (!mounted || request != generation) {
        next.dispose();
        return;
      }
      final old = thumbnail, oldController = thumbnailController;
      setState(() {
        thumbnail = next;
        thumbnailController = TicketLayoutController(next.template);
      });
      old?.dispose();
      oldController?.dispose();
    });
  }

  Future<void> edit() async {
    if (busy || unsupported) return;
    setState(() => busy = true);
    await ExceptionHandler.guard(context, futureFunction: () async {
      final r = await service.resolve(widget.occasionId, type,
          widget.feature.layout, widget.feature.ticketBackground);
      if (!mounted) {
        r.dispose();
        return;
      }
      final result = await showDialog<TicketLayoutResult>(
          context: context,
          useSafeArea: false,
          builder: (c) => Dialog.fullscreen(
              child: TicketLayoutEditor(
                  showTemplatePicker:
                      widget.feature.layout?['templates']?[type] == null &&
                          (widget.feature.ticketBackground?.isEmpty ?? true),
                  occasionId: widget.occasionId,
                  type: type,
                  layout: widget.feature.layout == null
                      ? null
                      : copyTicketJson(widget.feature.layout!),
                  background: widget.feature.ticketBackground,
                  resources: r,
                  service: service)));
      if (!mounted) return;
      if (result != null) {
        setState(() {
          widget.feature.ticketType = type;
          widget.feature.layout = {
            'schemaVersion': 1,
            'templates': {
              ...?(widget.feature.layout?['templates'] as Map?),
              type: result.template.toJson()
            }
          };
          widget.feature.ticketBackground = result.background;
        });
      }
      await refresh();
    });
    if (mounted) setState(() => busy = false);
  }

  @override
  Widget build(BuildContext context) =>
      Column(crossAxisAlignment: CrossAxisAlignment.center, children: [
        CheckboxListTile(
            value: widget.feature.canScanManually ?? false,
            title: Text(FeaturesStrings.enableManualTicketScan),
            subtitle: Text(FeaturesStrings.enableManualTicketScanDescription),
            onChanged: (v) =>
                setState(() => widget.feature.canScanManually = v)),
        CheckboxListTile(
            value: widget.feature.showHiddenNote ?? false,
            title: Text(FeaturesStrings.labelShowHiddenNote),
            subtitle: Text(FeaturesStrings.descriptionShowHiddenNote),
            onChanged: (v) =>
                setState(() => widget.feature.showHiddenNote = v)),
        const SizedBox(height: 12),
        if (unsupported) Text(TicketLayoutStrings.unsupported),
        if (thumbnail != null && !unsupported)
          SizedBox(
              height: 160,
              child: FittedBox(
                  fit: BoxFit.contain,
                  alignment: Alignment.center,
                  child: CustomPaint(
                      size: thumbnail!.template.area.size,
                      painter: TicketLayoutPainter(thumbnailController!,
                          thumbnail!, thumbnail!.scenarios['normal']!,
                          cropToTicket: true)))),
        const SizedBox(height: 8),
        if (widget.feature.conflictDraft != null)
          TextButton(
              onPressed: () {
                setState(() => widget.feature.restoreConflictDraft());
                refresh();
              },
              child: Text(TicketLayoutStrings.restoreDraft)),
        FilledButton.icon(
            onPressed: busy || unsupported || !RightsService.isUnitEditor()
                ? null
                : edit,
            icon: busy
                ? const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2))
                : const Icon(Icons.edit_outlined),
            label: Text(TicketLayoutStrings.edit)),
      ]);
}
