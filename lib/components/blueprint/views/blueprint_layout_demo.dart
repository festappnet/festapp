import '../blueprint_layout_resources.dart';
import 'blueprint_layout_background.dart';
import 'package:flutter/material.dart';
import 'package:venue_seat_picker/venue_seat_picker.dart';
import '../blueprint_strings.dart';
import '../../_shared/common_strings.dart';
import '../../_shared/editor_action_bar.dart';

/// Local geometry editor. Its optional save callback stores the wizard draft;
/// catalog, reservations and financial commands are never exposed here.
class BlueprintLayoutDemo extends StatefulWidget {
  const BlueprintLayoutDemo({super.key, this.initialDocument,
    this.initialResources, this.onSave, this.prepareResources, this.normalizeDocument, this.unitId, this.initiallyUnsaved = false});
  final VenueLayoutDocument Function(VenueLayoutDocument)? normalizeDocument;
  final bool initiallyUnsaved;
  final int? unitId;
  final Future<Map<String, dynamic>> Function(VenueLayoutDocument)? prepareResources;
  final VenueLayoutDocument? initialDocument;
  final Map<String, dynamic>? initialResources;
  final Future<void> Function(VenueLayoutDocument)? onSave;
  @override
  State<BlueprintLayoutDemo> createState() => _BlueprintLayoutDemoState();
}

class _BlueprintLayoutDemoState extends State<BlueprintLayoutDemo> {
  late final Future<Map<String, dynamic>> _resources = widget.initialResources != null
      ? Future.value(widget.initialResources!) : loadLayoutFixtureResources();
  final _assets = BlueprintLayoutAssetResolver();
  VenueLayoutController? _controller;
  VenueLayoutDocument? _saved;
  bool _pending = false;
  bool _savedOnce = false;
  String? _error;
  @override
  void dispose() {
    _assets.dispose();
    _controller?.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (_pending) return;
    setState(() { _pending = true; _error = null; });
    final document = widget.normalizeDocument?.call(_controller!.document) ?? _controller!.document;
    _controller!.apply(document);
    try {
      final resources = await widget.prepareResources?.call(document);
      if (!mounted) return;
      if (resources != null) {
        final current = _controller!.resources;
        if (!_controller!.setResources({...current, ...resources,
          'assets': {...resources['assets'] as Map? ?? {}, ...current['assets'] as Map? ?? {}},
          'images': {...resources['images'] as Map? ?? {}, ...current['images'] as Map? ?? {}},
        })) throw StateError('invalid_layout_resources');
      }
      await widget.onSave?.call(document);
      if (!mounted) return;
      _saved = document;
      _savedOnce = true;
      _controller!.markSaved();
    } catch (error) {
      if (mounted) setState(() => _error = error.toString());
    } finally {
      if (mounted) setState(() => _pending = false);
    }
  }

  @override
  Widget build(BuildContext context) => FutureBuilder<Map<String, dynamic>>(
    future: _resources,
    builder: (context, snapshot) {
      if (snapshot.hasError) return Center(child: Text(CommonStrings.unexpectedError));
      if (!snapshot.hasData) return const Center(child: CircularProgressIndicator());
      final controller = _controller ??= VenueLayoutController(
        widget.initialDocument ?? VenueLayoutTemplates.byId(VenueLayoutTemplates.defaultId).create(
          localize: VenueLayoutLocalizations.of(context).text),
        resources: snapshot.data!,
      );
      _saved ??= controller.document;
      return ListenableBuilder(listenable: controller, builder: (context, _) => PopScope(
        canPop: !_pending, child: Scaffold(
        body: Column(children: [
          MaterialBanner(
            content: Text(widget.onSave == null ? BlueprintStrings.demoGeometryNotice
                : BlueprintStrings.draftGeometryNotice),
            leading: const Icon(Icons.science_outlined),
            actions: [TextButton(onPressed: _pending ? null : () {
                controller.apply(_saved!); controller.markSaved();
              }, child: Text(CommonStrings.discardChanges))],
          ),
          if (widget.unitId != null) Row(children: [
            IconButton(tooltip: BlueprintStrings.background, icon: const Icon(Icons.image_outlined),
              onPressed: _pending ? null : () async {
                setState(() { _pending = true; _error = null; });
                try {
                  await pickBlueprintBackground(controller: controller, assets: _assets,
                    unitId: widget.unitId, isMounted: () => mounted);
                } catch (error) {
                  if (mounted) setState(() => _error = error.toString());
                } finally { if (mounted) setState(() => _pending = false); }
              }),
            if (controller.document.background != null)
              IconButton(tooltip: BlueprintStrings.removeBackground,
                icon: const Icon(Icons.hide_image_outlined),
                onPressed: _pending ? null : () => controller.apply(
                  controller.document.copyWith(clearBackground: true))),
          ]),
          if (_pending) const LinearProgressIndicator(),
          if (_error != null) Padding(padding: const EdgeInsets.all(8),
            child: Semantics(liveRegion: true, child: Text(_error!,
              style: TextStyle(color: Theme.of(context).colorScheme.error)))),
          Expanded(child: AbsorbPointer(absorbing: _pending,
            child: VenueLayoutEditor(controller: controller))),
        ]),
        bottomNavigationBar: EditorActionBar(
          hasChanges: controller.dirty || (widget.initiallyUnsaved && !_savedOnce),
          enabled: !_pending,
          onSave: _save,
          onDiscard: () async { controller.apply(_saved!); controller.markSaved(); },
        ),
      )));
    },
  );
}
