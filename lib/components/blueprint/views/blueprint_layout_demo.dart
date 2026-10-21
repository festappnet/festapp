import '../blueprint_layout_resources.dart';
import 'blueprint_plan_editor.dart';
import 'package:flutter/material.dart';
import 'package:venue_seat_picker/venue_seat_picker.dart';
import '../blueprint_strings.dart';
import '../../_shared/common_strings.dart';
import '../../_shared/editor_action_bar.dart';

/// Local geometry editor. Its optional save callback stores the wizard draft;
/// catalog, reservations and financial commands are never exposed here.
class BlueprintLayoutDemo extends StatefulWidget {
  const BlueprintLayoutDemo(
      {super.key,
      this.initialDocument,
      this.initialResources,
      this.loadTextResources,
      this.onSave,
      this.prepareResources,
      this.unitId,
      this.initiallyUnsaved = false});
  final Future<BlueprintTextResources> Function()? loadTextResources;
  final bool initiallyUnsaved;
  final int? unitId;
  final Future<Map<String, dynamic>> Function(
      VenueLayoutDocument, Map<String, dynamic>)? prepareResources;
  final VenueLayoutDocument? initialDocument;
  final Map<String, dynamic>? initialResources;
  final Future<void> Function(VenueLayoutDocument)? onSave;
  @override
  State<BlueprintLayoutDemo> createState() => _BlueprintLayoutDemoState();
}

class _BlueprintLayoutDemoState extends State<BlueprintLayoutDemo> {
  late final Future<Map<String, dynamic>> _resources =
      widget.initialResources != null
          ? Future.value(widget.initialResources!)
          : loadLayoutFixtureResources();
  VenueLayoutController? _controller;
  VenueLayoutDocument? _saved;
  Map<String, dynamic>? _savedResources;
  bool _pending = false;
  bool _editorBusy = false;
  bool _savedOnce = false;
  bool _allowPop = false;
  String? _error;
  @override
  void dispose() {
    _controller?.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (_pending || _editorBusy) return;
    setState(() {
      _pending = true;
      _error = null;
    });
    await finishBlueprintTextEditing();
    if (!mounted) return;
    final document = _controller!.document;
    try {
      final resources =
          await widget.prepareResources?.call(document, _controller!.resources);
      if (!mounted) return;
      if (resources != null && identical(document, _controller!.document)) {
        if (!commitBlueprintTextResources(_controller!, resources))
          throw StateError('invalid_layout_resources');
      }
      await widget.onSave?.call(document);
      if (!mounted) return;
      _saved = document;
      _savedResources = resources ?? _controller!.resources;
      _savedOnce = true;
      _controller!.setSavedBaseline(document);
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
          if (snapshot.hasError)
            return Center(child: Text(CommonStrings.unexpectedError));
          if (!snapshot.hasData)
            return const Center(child: CircularProgressIndicator());
          final controller = _controller ??= VenueLayoutController(
            widget.initialDocument ??
                VenueLayoutTemplates.byId(VenueLayoutTemplates.defaultId)
                    .create(
                        localize: VenueLayoutLocalizations.of(context).text),
            resources: snapshot.data!,
          );
          _saved ??= controller.document;
          _savedResources ??= controller.resources;
          return ListenableBuilder(
              listenable: controller,
              builder: (context, _) => PopScope(
                  canPop: !_pending &&
                      !_editorBusy &&
                      (_allowPop || !controller.dirty),
                  onPopInvokedWithResult: (didPop, result) async {
                    if (didPop || _pending || _editorBusy) return;
                    if (await confirmDiscardChanges(context) && mounted) {
                      setState(() => _allowPop = true);
                      WidgetsBinding.instance.addPostFrameCallback((_) {
                        if (mounted) Navigator.of(context).pop();
                      });
                    }
                  },
                  child: Scaffold(
                    body: Column(children: [
                      MaterialBanner(
                        content: Text(widget.onSave == null
                            ? BlueprintStrings.demoGeometryNotice
                            : BlueprintStrings.draftGeometryNotice),
                        leading: const Icon(Icons.science_outlined),
                        actions: [
                          TextButton(
                              onPressed: (_pending || _editorBusy)
                                  ? null
                                  : () {
                                      controller.apply(_saved!,
                                          preparedResources: _savedResources);
                                      controller.markSaved();
                                    },
                              child: Text(CommonStrings.discardChanges))
                        ],
                      ),
                      if (_pending) const LinearProgressIndicator(),
                      if (_error != null)
                        Padding(
                            padding: const EdgeInsets.all(8),
                            child: Semantics(
                                liveRegion: true,
                                child: Text(_error!,
                                    style: TextStyle(
                                        color: Theme.of(context)
                                            .colorScheme
                                            .error)))),
                      Expanded(
                          child: AbsorbPointer(
                              absorbing: _pending,
                              child: BlueprintPlanEditor(
                                  controller: controller,
                                  loadTextResources: widget.loadTextResources,
                                  unitId: widget.unitId,
                                  busy: _pending,
                                  onBusyChanged: (busy) {
                                    if (mounted)
                                      setState(() => _editorBusy = busy);
                                  }))),
                    ]),
                    bottomNavigationBar: EditorActionBar(
                      hasChanges: controller.dirty ||
                          (widget.initiallyUnsaved && !_savedOnce),
                      enabled: !_pending && !_editorBusy,
                      onSave: _save,
                      onDiscard: () async {
                        controller.apply(_saved!,
                            preparedResources: _savedResources);
                        controller.markSaved();
                      },
                    ),
                  )));
        },
      );
}
