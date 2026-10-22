import 'package:flutter/material.dart';
import '../../ticket_layout/ticket_layout_service.dart';
import '../../ticket_layout/ticket_layout_controller.dart';
import '../../ticket_layout/models/ticket_layout.dart';
import '../../ticket_layout/views/ticket_layout_canvas.dart';
import '../../ticket_layout/ticket_layout_strings.dart';
import '../../ticket_layout/ticket_preview_assets.dart';
import '../../ticket_layout/ticket_template_order.dart';
import 'occasion_setup_appearance.dart';

class OccasionSetupTicketChoice {
  const OccasionSetupTicketChoice(
      this.key, this.value, this.background, this.source);
  final String key;
  final Map<String, dynamic> value;
  final String? background;
  final Map<String, dynamic> source;
}

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
  final ValueChanged<OccasionSetupTicketChoice> onSelected;
  final String? selectedId;
  final Map<String, dynamic>? currentTemplate;
  @override
  State<OccasionSetupTicketGallery> createState() =>
      _OccasionSetupTicketGalleryState();
}

class _OccasionSetupTicketGalleryState
    extends State<OccasionSetupTicketGallery> {
  String _filter = 'all';
  Set<String> _activeKeys = {};
  final _prepared = <String, Future<void>>{};
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
    _prepared.clear();
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
    for (final controller in _controllers.values) controller.dispose();
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
          final entries = resources.presets.entries
              .where((entry) =>
                  _filter == 'all' ||
                  (_filter == 'named' &&
                      entry.value.elements
                          .any((e) => e.binding == 'orderName' && e.visible)) ||
                  (_filter == 'silk' &&
                      ['ball_silk', 'silk_light', 'silk_dark']
                          .contains(entry.key)))
              .toList()
            ..sort((a, b) => compareTicketTemplateKeys(a.key, b.key));
          _activeKeys = {'current', ...entries.map((e) => e.key)};
          for (final key in _controllers.keys.toList()) {
            if (!_activeKeys.contains(key)) {
              _controllers.remove(key)?.dispose();
              _prepared.remove(key);
              _styledResources?.artworks.remove(key)?.image?.dispose();
            }
          }
          return LayoutBuilder(builder: (context, constraints) {
            final columns = constraints.maxWidth < 600
                ? 1
                : constraints.maxWidth < 1000
                    ? 2
                    : 3;
            final width = (constraints.maxWidth - (columns - 1) * 12) / columns;
            return Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text('Vyberte výchozí návrh vstupenky',
                      style: Theme.of(context).textTheme.titleMedium),
                  const SizedBox(height: 8),
                  const Text(
                      'Vstupenka převezme vybrané barvy a písmo. Šablonu si můžete dále upravit v editoru - změnit texty, jejich rozmístění i pozadí.'),
                  const SizedBox(height: 16),
                  Wrap(spacing: 8, runSpacing: 8, children: [
                    for (final option in {
                      'all': 'Všechny (${resources.presets.length})',
                      'named': 'Se jménem',
                      'silk': 'Hedvábí'
                    }.entries)
                      ChoiceChip(
                          label: Text(option.value),
                          selected: _filter == option.key,
                          onSelected: (_) => setState(() {
                                _filter = option.key;
                              })),
                  ]),
                  const SizedBox(height: 12),
                  Wrap(spacing: 12, runSpacing: 12, children: [
                    for (final entry in entries)
                      _card(context, resources, entry, width),
                    if (widget.currentTemplate != null &&
                        (widget.selectedId == null ||
                            !resources.presets.containsKey(widget.selectedId)))
                      _card(
                          context,
                          resources,
                          MapEntry('current',
                              TicketTemplate.fromJson(widget.currentTemplate!)),
                          width,
                          current: true),
                  ]),
                ]);
          });
        },
      );
  final _controllers = <String, TicketLayoutController>{};
  Widget _card(BuildContext context, TicketLayoutResources resources,
      MapEntry<String, TicketTemplate> entry, double width,
      {bool current = false}) {
    final decorated = resources.artworks.containsKey(entry.key);
    final raw = current
        ? entry.value.toJson()
        : OccasionSetupAppearance.styledTemplate(
            entry.value.toJson(), widget.appearance,
            decorated: decorated, composition: entry.key);
    final previous = _controllers[entry.key];
    final template = TicketTemplate.fromJson(raw);
    final controller = previous != null && previous.document == template
        ? previous
        : TicketLayoutController(template,
            artworkKey: decorated ? entry.key : null);
    if (previous != controller) previous?.dispose();
    _controllers[entry.key] = controller;
    final background = (decorated
            ? OccasionSetupAppearance.ticketBackground(
                entry.key, widget.appearance)
            : null) ??
        resources.artworks[entry.key]?.background;
    final selected = current || widget.selectedId == entry.key;
    final label = current
        ? 'Aktuální vstupenka'
        : OccasionSetupAppearance.ticketCompositions[entry.key] ??
            resources.artworks[entry.key]?.label ??
            TicketLayoutStrings.binding('style_${entry.key}');
    return SizedBox(
        width: width,
        child: Semantics(
            selected: selected,
            child: OutlinedButton(
              key: ValueKey('setup-ticket-template-${entry.key}'),
              onPressed: current
                  ? () {}
                  : () => widget.onSelected(OccasionSetupTicketChoice(
                      entry.key, raw, background, entry.value.toJson())),
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
                          future: _prepared.putIfAbsent(entry.key, () async {
                            if (!current && decorated) {
                              if (decorated &&
                                  background !=
                                      resources
                                          .artworks[entry.key]?.background) {
                                final image = await TicketPreviewAssets.shared
                                    .image(background!);
                                if (!mounted ||
                                    !resources.isValid ||
                                    !_activeKeys.contains(entry.key)) {
                                  image?.dispose();
                                  throw StateError('Gallery closed');
                                }
                                _styledResources!.artworks[entry.key] =
                                    TicketLayoutArtwork(
                                        label: null,
                                        background: background,
                                        image: image);
                              } else {
                                await resources.prepareStyle(entry.key);
                                if (!mounted ||
                                    !_activeKeys.contains(entry.key)) return;
                                final artwork = resources.artworks[entry.key];
                                if (artwork != null) {
                                  _styledResources!.artworks[entry.key] =
                                      TicketLayoutArtwork(
                                          label: artwork.label,
                                          background: artwork.background,
                                          image: artwork.image?.clone());
                                }
                              }
                            }
                            await (current ? resources : _styledResources!)
                                .prepareTemplate(controller.document);
                          }),
                          builder: (context, snapshot) {
                            if (snapshot.hasError)
                              return const Text(
                                  'Náhled vstupenky se nepodařilo načíst.');
                            if (snapshot.connectionState !=
                                ConnectionState.done)
                              return const Center(
                                  child: CircularProgressIndicator());
                            return FittedBox(
                                child: CustomPaint(
                              size: controller.document.area.size,
                              painter: TicketLayoutPainter(
                                  controller,
                                  current ? resources : _styledResources!,
                                  resources.previewData(
                                      controller.document, 'normal'),
                                  cropToTicket: true),
                            ));
                          }),
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
