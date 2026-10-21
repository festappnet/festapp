import '../blueprint_font_selection.dart';
import 'blueprint_editor_feedback.dart';
import 'package:fstapp/widgets/app_dialog.dart';
import 'package:venue_seat_picker/editor_ui.dart';
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:venue_seat_picker/venue_seat_picker.dart';
import '../../_shared/common_strings.dart';
import '../../fonts/font_family_picker.dart';
import '../blueprint_layout_resources.dart';
import '../blueprint_strings.dart';
import '../blueprint_text_preparation.dart';
import 'blueprint_layout_background.dart';

/// Close native composition before either host captures a save snapshot.
Future<void> finishBlueprintTextEditing() async {
  final focus = FocusManager.instance.primaryFocus;
  final focusedContext = focus?.context;
  final editable = focusedContext?.widget is EditableText
      ? focusedContext!.widget as EditableText
      : focusedContext?.findAncestorStateOfType<EditableTextState>()?.widget;
  editable?.controller.clearComposing();
  focus?.unfocus();
  await WidgetsBinding.instance.endOfFrame;
}

/// The single Festapp plan editor, shared by setup and existing occasions.
/// Hosts provide persistence, authorization scope and commercial presentation.
class BlueprintPlanEditor extends StatefulWidget {
  const BlueprintPlanEditor(
      {super.key,
      required this.controller,
      this.loadTextResources,
      this.occasionId,
      this.unitId,
      this.busy = false,
      this.onBusyChanged,
      this.toolbarPrefix,
      this.toolbarLeading,
      this.toolbarTrailing,
      this.footerTrailing,
      this.canvasBottomOverlay,
      this.canvasHeader,
      this.onRenameNode,
      this.inspectorOverride,
      this.libraryOverride,
      this.viewSelection,
      this.onViewSelectionChanged,
      this.viewSelectionTarget,
      this.viewSelectableIds,
      this.readOnlyLabelNodeIds = const {},
      this.seatPresentation = const {},
      this.interactionEnabled = true,
      this.showGallery = true,
      this.onEditRequested,
      this.onNodeActivated});
  final VenueLayoutController controller;
  final Future<BlueprintTextResources> Function()? loadTextResources;
  final int? occasionId, unitId;
  final bool busy, interactionEnabled, showGallery;
  final ValueChanged<bool>? onBusyChanged;
  final Widget? toolbarPrefix,
      toolbarLeading,
      toolbarTrailing,
      footerTrailing,
      canvasBottomOverlay,
      canvasHeader,
      inspectorOverride,
      libraryOverride;
  final void Function(LayoutNode, String)? onRenameNode;
  final Set<String>? viewSelection, viewSelectableIds;
  final ValueChanged<Set<String>>? onViewSelectionChanged;
  final String Function(String)? viewSelectionTarget;
  final Set<String> readOnlyLabelNodeIds;
  final Map<String, dynamic> seatPresentation;
  final ValueChanged<String>? onNodeActivated;
  final ValueChanged<Set<String>>? onEditRequested;
  @override
  State<BlueprintPlanEditor> createState() => _BlueprintPlanEditorState();
}

class _BlueprintPlanEditorState extends State<BlueprintPlanEditor> {
  VenueLayoutController get controller => widget.controller;
  Future<BlueprintTextResources> get _fonts => widget.loadTextResources!();
  final _assets = BlueprintLayoutAssetResolver();
  int _fontGeneration = 0;
  Timer? _debounce;
  VenueLayoutDocument? _observed;
  bool _pending = false, _preparing = false, _failed = false;
  String? _error;
  final Map<String, String> _changedFonts = {};
  bool _fontPreviewActive = false;
  VenueLayoutController? _fontPreviewController;
  bool get _busy => widget.busy || _pending;
  bool get _editing => widget.interactionEnabled && !controller.readOnly;
  @override
  void initState() {
    super.initState();
    controller.addListener(_schedule);
    _schedule();
  }

  @override
  void didUpdateWidget(covariant BlueprintPlanEditor oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(oldWidget.controller, controller)) {
      oldWidget.controller.removeListener(_schedule);
      _cancelFontPreview();
      controller.addListener(_schedule);
      _observed = null;
      _fontGeneration++;
      _inlineFaces.clear();
      _changedFonts.clear();
    }
    if (!widget.interactionEnabled) {
      _debounce?.cancel();
      _preparing = false;
      _observed = null;
    }
    _schedule();
  }

  @override
  void dispose() {
    _fontGeneration++;
    _debounce?.cancel();
    controller.removeListener(_schedule);
    _cancelFontPreview();
    _assets.dispose();
    super.dispose();
  }

  Map<String, dynamic> _editorFamilies(
      VenueLayoutDocument document, BlueprintTextResources provider,
      {String? selected}) {
    final ids = {
      if (selected != null) selected,
      resolveNodeAppearance(
              document,
              LayoutNode(
                  id: '00000000-0000-4000-8000-000000000000', kind: 'text'))
          .label['fontFamilyId'],
      for (final node in document.nodes)
        resolveNodeAppearance(document, node).label['fontFamilyId'],
    };
    return {
      ...controller.resources['fontFamilies'] as Map? ?? {},
      for (final family in provider.families)
        if (ids.contains(family['id'])) family['id'] as String: family
    };
  }

  void _schedule() {
    if (!_editing ||
        widget.loadTextResources == null ||
        _preparing ||
        _observed != null) return;
    final session = controller;
    _observed = session.document;
    _debounce = Timer(Duration.zero, () async {
      if (!mounted) return;
      setState(() {
        _preparing = true;
        _failed = false;
      });
      try {
        final provider = await _fonts;
        if (!mounted || !identical(session, controller)) return;
        if (!session.setResources({
          ...session.resources,
          'fontFamilies': _editorFamilies(session.document, provider)
        })) throw StateError('invalid_layout_resources');
      } catch (error) {
        if (mounted && identical(session, controller))
          setState(() {
            _failed = true;
            _error = BlueprintStrings.layoutErrorMessage(error);
          });
      } finally {
        if (mounted && identical(session, controller))
          setState(() => _preparing = false);
      }
    });
  }

  Future<void> _run(Future<void> Function() action) async {
    if (_busy || !_editing) return;
    setState(() {
      _pending = true;
      _error = null;
    });
    widget.onBusyChanged?.call(true);
    try {
      await action();
    } catch (error) {
      if (mounted)
        setState(() => _error = BlueprintStrings.layoutErrorMessage(error));
    } finally {
      if (mounted) {
        setState(() => _pending = false);
        widget.onBusyChanged?.call(false);
      }
    }
  }

  Future<void> _upload({required bool graphic}) async {
    final session = controller;
    final selection = await showBlueprintBackgroundPicker(context,
        graphic: graphic,
        extensions: graphic ? blueprintGraphicExtensions : null);
    if (selection == null ||
        !mounted ||
        !identical(session, controller) ||
        _busy) return;
    await _run(() async {
      if (graphic) {
        await uploadBlueprintGraphic(
            selection: selection,
            controller: controller,
            assets: _assets,
            isMounted: () => mounted && identical(session, controller),
            occasionId: widget.occasionId,
            unitId: widget.unitId,
            prepareText: (text) async {
              final provider = await _fonts;
              return BlueprintSvgTextPreparation(
                      {for (final f in provider.families) f['id'] as String: f},
                      provider.prepareTextBatch)
                  .call(text);
            });
      } else {
        await uploadBlueprintBackground(
            selection: selection,
            controller: controller,
            assets: _assets,
            isMounted: () => mounted && identical(session, controller),
            occasionId: widget.occasionId,
            unitId: widget.unitId);
      }
    });
  }

  Future<void> _prepareFonts(
      {String? selectedFont, String? nodeId, String? appearanceKind}) async {
    final generation = ++_fontGeneration;
    final provider = await _fonts;
    if (!mounted || generation != _fontGeneration) {
      throw StateError(BlueprintStrings.draftChanged);
    }
    final document = controller.document;
    if (document.schemaVersion == 2) {
      final styles = Map<String, dynamic>.from(document.styles);
      VenueLayoutDocument next = document;
      if (nodeId != null) {
        next = document.copyWith(nodes: [
          for (final node in document.nodes)
            node.id == nodeId
                ? node.copyWith(
                    style: patchCanonicalStyle(
                        node.style, ['label', 'fontFamilyId'],
                        value: selectedFont, unset: selectedFont == null))
                : node
        ]);
      } else if (appearanceKind != null && appearanceKind != 'document') {
        final kinds = Map<String, dynamic>.from(styles['kinds'] as Map? ?? {});
        kinds[appearanceKind] = patchCanonicalStyle(
            Map<String, dynamic>.from(kinds[appearanceKind] as Map? ?? {}),
            ['label', 'fontFamilyId'],
            value: selectedFont,
            unset: selectedFont == null);
        styles['kinds'] = kinds;
        next = document.copyWith(styles: styles);
      } else {
        final label = Map<String, dynamic>.from(styles['label'] as Map? ?? {});
        if (selectedFont == null) {
          label.remove('fontFamilyId');
        } else {
          label['fontFamilyId'] = selectedFont;
        }
        if (label.isEmpty) {
          styles.remove('label');
        } else {
          styles['label'] = label;
        }
        next = document.copyWith(styles: styles);
      }
      final families = _editorFamilies(next, provider, selected: selectedFont);
      next = normalizeBlueprintFontSelection(document, next, families,
          nodeId: nodeId, appearanceKind: appearanceKind);
      if (!controller.apply(next, preparedResources: {
        ...controller.resources,
        'fontFamilies': families
      })) throw StateError(controller.error ?? 'font_change_rejected');
      return;
    }
    throw const FormatException('canonical_document_required');
  }

  final Map<String, Future<TextStyle>> _inlineFaces = {};
  Future<TextStyle> _inlineTextStyle(LayoutNode node) async {
    final document = controller.document;
    final provider = await _fonts;
    if (!mounted) throw StateError(BlueprintStrings.draftChanged);
    final face = resolvedLayoutFontFace(
        resolveNodeAppearance(document, node).label,
        {for (final f in provider.families) f['id'] as String: f},
        nodeId: node.id);
    try {
      return await _inlineFaces.putIfAbsent(face, () async {
        final font = await provider.loadFace(face);
        // Each loader name owns one actual face. Asking Flutter for synthetic
        // weight or italic here would apply an additional transformation.
        return TextStyle(
            fontFamily: font.loaderName,
            fontWeight: FontWeight.normal,
            fontStyle: FontStyle.normal);
      });
    } catch (_) {
      _inlineFaces.remove(face);
      rethrow;
    }
  }

  Future<TextStyle> _fontPreviewStyle(
      BlueprintTextResources provider, String family) async {
    final entry = provider.families.firstWhere((e) => e['family'] == family);
    final faces = entry['faces'] as Map;
    final face = faces['400:normal'] ?? faces.values.first;
    final font = await provider.loadFace(face as String);
    return TextStyle(fontFamily: font.loaderName, fontWeight: FontWeight.w400);
  }

  Widget _objectFontPicker(BuildContext context, LayoutNode node) =>
      _labelFontPicker(context, node: node);

  Widget _globalFontPicker(BuildContext context, String kind) =>
      _labelFontPicker(context, appearanceKind: kind);

  void _cancelFontPreview() {
    if (!_fontPreviewActive) return;
    _fontPreviewActive = false;
    ++_fontGeneration;
    final session = _fontPreviewController;
    _fontPreviewController = null;
    session?.cancelGesture();
  }

  Future<void> _previewFont(String? familyId,
      {String? nodeId, String? kind}) async {
    if (!_editing || _busy) return;
    if (!_fontPreviewActive) {
      if (controller.gestureActive) return;
      controller.beginGesture();
      _fontPreviewController = controller;
      _fontPreviewActive = true;
    }
    await _prepareFonts(
        selectedFont: familyId, nodeId: nodeId, appearanceKind: kind);
  }

  Widget _labelFontPicker(BuildContext context,
          {LayoutNode? node, String? appearanceKind}) =>
      FutureBuilder<BlueprintTextResources>(
        future: _fonts,
        builder: (context, snapshot) {
          final provider = snapshot.data;
          if (provider == null) {
            return const SizedBox(height: 48);
          }
          final catalog = provider.families;
          final document = controller.document;
          Object? id;
          {
            if (node != null) {
              id = resolveNodeAppearance(document, node).label['fontFamilyId'];
            } else if (appearanceKind == 'document') {
              id = (document.styles['label'] as Map?)?['fontFamilyId'];
            } else {
              id = resolveNodeAppearance(
                      document,
                      LayoutNode(
                          id: '00000000-0000-4000-8000-000000000000',
                          kind: appearanceKind ?? 'text'))
                  .label['fontFamilyId'];
            }
          }
          final scope =
              node != null ? 'node:${node.id}' : 'kind:$appearanceKind';
          final selected = catalog.where((font) => font['id'] == id);
          return Padding(
              padding: const EdgeInsets.only(bottom: 16),
              child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                FontFamilyPicker(
                  value: selected.isEmpty
                      ? null
                      : selected.first['family'] as String,
                  enabled: !_busy &&
                      !controller.readOnly &&
                      !(node?.locked ?? false),
                  families:
                      catalog.map((font) => font['family'] as String).toList(),
                  extraFamilies: catalog
                      .where((font) => font['source'] == 'bundled')
                      .map((font) => font['family'] as String)
                      .toList(),
                  previewStyle: (family) => _fontPreviewStyle(provider, family),
                  onPreview: (family) => _previewFont(
                      family == null
                          ? null
                          : catalog.firstWhere(
                                  (font) => font['family'] == family)['id']
                              as String,
                      nodeId: node?.id,
                      kind: appearanceKind),
                  onPreviewEnd: _cancelFontPreview,
                  onSelected: (family) async {
                    _cancelFontPreview();
                    final selectedId = family == null
                        ? null
                        : catalog.firstWhere(
                            (font) => font['family'] == family)['id'] as String;
                    await _run(() async {
                      await _prepareFonts(
                          selectedFont: selectedId,
                          nodeId: node?.id,
                          appearanceKind: appearanceKind);
                      if (mounted && selectedId != null && selectedId != id) {
                        setState(() => _changedFonts[scope] = selectedId);
                      }
                    });
                  },
                ),
                if (id is String &&
                    appearanceKind != 'document' &&
                    _changedFonts[scope] == id &&
                    (document.styles['label'] as Map?)?['fontFamilyId'] != id)
                  Padding(
                      padding: const EdgeInsets.only(top: 8, bottom: 16),
                      child: Align(
                          alignment: Alignment.centerLeft,
                          child: TextButton.icon(
                            key: const ValueKey('set-default-plan-font'),
                            icon: const Icon(Icons.text_fields, size: 18),
                            label: Text(VenueLayoutStrings.text(
                                context, 'Set as default font for the plan')),
                            onPressed: _busy ||
                                    controller.readOnly ||
                                    (controller.document.styles['label']
                                            as Map?)?['fontFamilyId'] ==
                                        id
                                ? null
                                : () => _run(() => _prepareFonts(
                                    selectedFont: id as String,
                                    appearanceKind: 'document')),
                          ))),
              ]));
        },
      );

  @override
  Widget build(BuildContext context) => Theme(
      data: Theme.of(context).copyWith(
        expansionTileTheme: Theme.of(context).expansionTileTheme.copyWith(
            shape: const Border(),
            collapsedShape: const Border(),
            childrenPadding: const EdgeInsets.only(top: 8, bottom: 8)),
        textButtonTheme: TextButtonThemeData(
            style: (Theme.of(context).textButtonTheme.style ??
                    const ButtonStyle())
                .copyWith(
                    shape: const WidgetStatePropertyAll(StadiumBorder()),
                    minimumSize: const WidgetStatePropertyAll(Size(44, 44)))),
        filledButtonTheme: FilledButtonThemeData(
            style: (Theme.of(context).filledButtonTheme.style ??
                    const ButtonStyle())
                .copyWith(
                    shape: const WidgetStatePropertyAll(StadiumBorder()),
                    minimumSize: const WidgetStatePropertyAll(Size(44, 44)))),
        outlinedButtonTheme: OutlinedButtonThemeData(
            style: (Theme.of(context).outlinedButtonTheme.style ??
                    const ButtonStyle())
                .copyWith(
                    shape: const WidgetStatePropertyAll(StadiumBorder()),
                    minimumSize: const WidgetStatePropertyAll(Size(44, 44)))),
        segmentedButtonTheme: SegmentedButtonThemeData(
            style: (Theme.of(context).segmentedButtonTheme.style ??
                    const ButtonStyle())
                .copyWith(
                    shape: const WidgetStatePropertyAll(StadiumBorder()),
                    minimumSize: const WidgetStatePropertyAll(Size(44, 44)))),
      ),
      child: EditorColorDialogTheme(
          builder: (context, dialog) => AppAlertDialog(
              title: dialog.title, content: dialog.content, actions: dialog.actions,
              alignment: MediaQuery.sizeOf(context).width >= 900
                  ? Alignment.centerRight : Alignment.center,
              insetPadding: const EdgeInsets.all(16)),
          child: BlueprintEditorFeedback(
          message: _error, onDismiss: () => setState(() => _error = null),
          child: Column(children: [
        if (_failed)
          TextButton(
              onPressed: () {
                _observed = null;
                _schedule();
              },
              child: Text(CommonStrings.retry)),
        Expanded(
            child: AbsorbPointer(
                absorbing: _pending,
                child: VenueLayoutEditor(
                    controller: controller,
                    toolbarPrefix: widget.toolbarPrefix,
                    toolbarLeading: widget.toolbarLeading,
                    footerTrailing: widget.footerTrailing,
                    libraryActions: _editing &&
                            (widget.occasionId != null || widget.unitId != null)
                        ? Column(children: [
                            ListTile(
                                dense: true,
                                contentPadding: EdgeInsets.zero,
                                leading: const Icon(
                                    Icons.add_photo_alternate_outlined),
                                title: Text(VenueLayoutStrings.text(
                                    context, 'Insert image / SVG')),
                                onTap: _busy
                                    ? null
                                    : () => _upload(graphic: true)),
                            ListTile(
                                dense: true,
                                contentPadding: EdgeInsets.zero,
                                leading: const Icon(Icons.image_outlined),
                                title: Text(BlueprintStrings.background),
                                onTap: _busy
                                    ? null
                                    : () => _upload(graphic: false)),
                            if (controller.document.background != null)
                              ListTile(
                                  dense: true,
                                  contentPadding: EdgeInsets.zero,
                                  leading:
                                      const Icon(Icons.hide_image_outlined),
                                  title:
                                      Text(BlueprintStrings.removeBackground),
                                  onTap: _busy
                                      ? null
                                      : () => controller.apply(
                                          controller.document
                                              .copyWith(clearBackground: true),
                                          label: BlueprintStrings
                                              .removeBackground)),
                          ])
                        : null,
                    toolbarTrailing: widget.toolbarTrailing,
                    onRenameNode: widget.onRenameNode,
                    inlineTextStyleBuilder: widget.loadTextResources == null
                        ? null
                        : _inlineTextStyle,
                    fontPickerBuilder: widget.loadTextResources == null
                        ? null
                        : _objectFontPicker,
                    globalFontPickerBuilder: widget.loadTextResources == null
                        ? null
                        : _globalFontPicker,
                    inspectorOverride: widget.inspectorOverride,
                    libraryOverride: widget.libraryOverride,
                    canvasBottomOverlay: widget.canvasBottomOverlay,
                    canvasHeader: widget.canvasHeader,
                    viewSelection: widget.viewSelection,
                    onViewSelectionChanged: widget.onViewSelectionChanged,
                    viewSelectionTarget: widget.viewSelectionTarget,
                    viewSelectableIds: widget.viewSelectableIds,
                    readOnlyLabelNodeIds: widget.readOnlyLabelNodeIds,
                    seatPresentation: widget.seatPresentation,
                    interactionEnabled: widget.interactionEnabled,
                    showGallery: widget.showGallery,
                    onEditRequested: widget.onEditRequested,
                    onNodeActivated: widget.onNodeActivated))),
      ]))));
}
