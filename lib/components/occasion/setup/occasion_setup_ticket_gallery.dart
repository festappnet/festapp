import 'package:flutter/material.dart';
import '../../ticket_layout/ticket_layout_service.dart';
import '../../ticket_layout/ticket_layout_controller.dart';
import '../../ticket_layout/models/ticket_layout.dart';
import '../../ticket_layout/views/ticket_layout_canvas.dart';
import '../../ticket_layout/ticket_layout_strings.dart';
import 'occasion_setup_appearance.dart';

/// Real ticket renderer and canonical template catalog, styled before choosing.
class OccasionSetupTicketGallery extends StatefulWidget {
  const OccasionSetupTicketGallery(
      {super.key,
      required this.loadResources,
      required this.appearance,
      required this.onSelected,
      this.selectedId,
      this.currentTemplate});
  final Future<TicketLayoutResources> Function() loadResources;
  final Map<String, dynamic> appearance;
  final ValueChanged<MapEntry<String, Map<String, dynamic>>> onSelected;
  final String? selectedId;
  final Map<String, dynamic>? currentTemplate;
  @override
  State<OccasionSetupTicketGallery> createState() =>
      _OccasionSetupTicketGalleryState();
}

class _OccasionSetupTicketGalleryState
    extends State<OccasionSetupTicketGallery> {
  TicketLayoutResources? _resources;
  TicketLayoutResources? _styledResources;
  // The loader can flush its parent's draft. Start after the build that mounts
  // this gallery so that save-state notifications cannot run during build.
  late Future<TicketLayoutResources> _pending = Future(_load);
  Future<TicketLayoutResources> _load() async {
    if (!mounted) throw StateError('Gallery closed');
    final resources = await widget.loadResources();
    if (!mounted) {
      resources.dispose();
      throw StateError('Gallery closed');
    }
    // Each resource owner retains its own image handles.
    _styledResources?.dispose();
    _styledResources = TicketLayoutResources(
        template: resources.template,
        identity: resources.identity,
        loadFonts: resources.loadFonts,
        preset: resources.preset,
        presets: resources.presets,
        scenarios: resources.scenarios,
        metrics: resources.metrics,
        fonts: resources.fonts,
        catalog: resources.catalog,
        logo: resources.logo?.clone(),
        qrSize: resources.qrSize,
        qrModules: resources.qrModules);
    _resources?.dispose();
    _resources = resources;
    return resources;
  }

  @override
  void dispose() {
    _resources?.dispose();
    _styledResources?.dispose();
    for(final controller in _controllers.values) controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => FutureBuilder<TicketLayoutResources>(
        future: _pending,
        builder: (context, snapshot) {
          if (snapshot.hasError)
            return Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('Náhledy vstupenek se nepodařilo načíst.'),
                  TextButton(
                      onPressed: () => setState(() {
                            _pending = Future(_load);
                          }),
                      child: const Text('Zkusit znovu')),
                ]);
          if (!snapshot.hasData)
            return const Center(child: CircularProgressIndicator());
          final resources = snapshot.data!;
          return LayoutBuilder(
              builder: (context, constraints) =>
                  Wrap(spacing: 12, runSpacing: 12, children: [
                    if (widget.currentTemplate != null &&
                        widget.selectedId == null)
                      _card(
                          context,
                          resources,
                          MapEntry('current',
                              TicketTemplate.fromJson(widget.currentTemplate!)),
                          constraints.maxWidth < 600
                              ? constraints.maxWidth
                              : (constraints.maxWidth - 12) / 2,
                          current: true),
                    for (final entry in resources.presets.entries)
                      _card(
                          context,
                          resources,
                          entry,
                          constraints.maxWidth < 600
                              ? constraints.maxWidth
                              : (constraints.maxWidth - 12) / 2),
                  ]));
        },
      );
  final _controllers = <String,TicketLayoutController>{};
  Widget _card(BuildContext context, TicketLayoutResources resources,
      MapEntry<String, TicketTemplate> entry, double width,
      {bool current = false}) {
    final raw = current
        ? entry.value.toJson()
        : OccasionSetupAppearance.styledTemplate(
            entry.value.toJson(), widget.appearance);
    final previous=_controllers[entry.key];
    final template=TicketTemplate.fromJson(raw);
    final controller=previous != null && previous.document == template ? previous : TicketLayoutController(template);
    if(previous != controller) previous?.dispose();
    _controllers[entry.key]=controller;
    final selected = current || widget.selectedId == entry.key;
    final label = current
        ? 'Aktuální vstupenka'
        : resources.artworks[entry.key]?.label ??
            TicketLayoutStrings.binding('style_${entry.key}');
    return SizedBox(
        width: width,
        child: Semantics(
            selected: selected,
            child: OutlinedButton(
              key: ValueKey('setup-ticket-template-${entry.key}'),
              onPressed: current
                  ? () {}
                  : () => widget.onSelected(MapEntry(entry.key, raw)),
              style: OutlinedButton.styleFrom(
                  padding: const EdgeInsets.all(12),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(16)),
                  side: BorderSide(
                      color: selected
                          ? Theme.of(context).colorScheme.primary
                          : Theme.of(context).colorScheme.outline,
                      width: selected ? 2 : 1)),
              child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    SizedBox(
                        height: 180,
                        child: FutureBuilder<void>(
                          future: (current ? resources : _styledResources!).prepareTemplate(controller.document),
                          builder:(context,snapshot) {
                            if(snapshot.hasError) return const Text('Písmo náhledu se nepodařilo načíst.');
                            if(snapshot.connectionState != ConnectionState.done) return const Center(child:CircularProgressIndicator());
                            return FittedBox(child: CustomPaint(
                          size: controller.document.area.size,
                          painter: TicketLayoutPainter(
                              controller,
                              current ? resources : _styledResources!,
                              resources.previewData(
                                  controller.document, 'normal'),
                              cropToTicket: true),
                        ));}),
                    ),
                    const SizedBox(height: 12),
                    Row(children: [
                      Expanded(child: Text(label)),
                      SizedBox(
                          width: 24,
                          height: 24,
                          child: selected ? const Icon(Icons.check) : null)
                    ]),
                  ]),
            )));
  }
}
