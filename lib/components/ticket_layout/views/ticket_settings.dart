import 'package:fstapp/components/features/features_strings.dart';
import '../ticket_delivery_strings.dart';
import 'ticket_delivery_selector.dart';
import 'ticket_delivery_preview.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:fstapp/data_services/authorization_capabilities.dart';
import 'package:fstapp/widgets/app_dialog.dart';
import 'package:auto_route/auto_route.dart';
import 'package:fstapp/components/navigation/routed_day_tabs.dart';
import 'package:fstapp/components/_shared/editor_draft_scope.dart';
import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:fstapp/components/features/ticket_feature.dart';
import 'package:fstapp/data_services/rights_service.dart';
import 'package:fstapp/services/exception_handler.dart';
import '../models/ticket_layout.dart';
import '../ticket_layout_controller.dart';
import '../ticket_layout_service.dart';
import '../ticket_layout_strings.dart';
import 'ticket_layout_editor.dart';
import 'ticket_layout_canvas.dart';
import 'ticket_scanning_settings.dart';

class TicketSettings extends StatefulWidget {
  final TicketFeature feature;
  final int occasionId;
  final bool productEditing, borrowResourcesOnly, readOnly;
  final Future<void> Function(TicketFeature)? onSave;
  final TicketLayoutService service;
  final TicketPreviewOccasion? previewOccasion;
  final bool showScanningSettings;
  final bool showPreview;
  final bool showDeliverySelector;
  TicketSettings(
      {super.key,
      required this.feature,
      required this.occasionId,
      this.onSave,
      this.productEditing = true,
      this.readOnly = false,
      this.borrowResourcesOnly = false,
      this.previewOccasion,
      this.showScanningSettings = true,
      this.showPreview = true,
      this.showDeliverySelector = true,
      TicketLayoutService? service})
      : service = service ?? TicketLayoutService();
  @override
  State<TicketSettings> createState() => _TicketSettingsState();
}

class _TicketSettingsState extends State<TicketSettings> {
  void _refresh(VoidCallback change) {
    setState(change);
    EditorDraftScope.changed(context);
  }

  TicketLayoutService get service => widget.previewOccasion == null
      ? widget.service
      : widget.service.withPreviewOccasion(widget.previewOccasion!);

  @override
  void didUpdateWidget(covariant TicketSettings oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.showPreview && !_editorOpen && _thumbnailKey != _contextKey)
      refresh();
  }

  Future<void>? _loading;
  String? _thumbnailKey;
  String get _contextKey => jsonEncode([
        TicketLayoutService.identityKey(),
        widget.occasionId,
        widget.feature.deliveryMode.value,
        widget.service.setupDraftId,
        widget.service.setupRevision,
        type,
        widget.feature.layout,
        widget.feature.ticketBackground,
        widget.previewOccasion?.toJson(),
        widget.readOnly,
        widget.borrowResourcesOnly,
        RightsService.currentOccasion()?.aggregateVersion
      ]);
  TicketLayoutResources? thumbnail;
  TicketLayoutController? thumbnailController;
  bool busy = false;
  int generation = 0;
  // Keep the persisted slot for compatibility; visual choices belong to templates.
  String get type => widget.feature.ticketType == 'named' ? 'named' : 'wide';
  bool get unsupported =>
      widget.feature.layout != null &&
      widget.feature.layout!['schemaVersion'] != 3;
  @override
  void initState() {
    super.initState();
    RightsService.occasionLinkModelNotifier.addListener(_contextChanged);
    try {
      _authChanges = Supabase.instance.client.auth.onAuthStateChange
          .listen((_) => _contextChanged());
    } catch (_) {}
    if (widget.showPreview)
      WidgetsBinding.instance.addPostFrameCallback((_) => refresh());
  }

  @override
  void dispose() {
    generation++;
    RightsService.occasionLinkModelNotifier.removeListener(_contextChanged);
    _authChanges?.cancel();
    thumbnail?.dispose();
    thumbnailController?.dispose();
    super.dispose();
  }

  Future<void> refresh() {
    if (!widget.feature.deliveryMode.includesPdf) return Future.value();
    if (_loading != null) return _loading!;
    final key = _contextKey;
    return _loading = _refreshPreview().whenComplete(() {
      _loading = null;
      if (mounted && widget.showPreview && key != _contextKey)
        unawaited(refresh());
    });
  }

  Future<void> _refreshPreview() async {
    final key = _contextKey;
    final request = ++generation;
    if (unsupported) return;
    await ExceptionHandler.guard(context, futureFunction: () async {
      final next = await service.resolve(widget.occasionId, type,
          widget.feature.layout, widget.feature.ticketBackground,
          borrowResourcesOnly: widget.borrowResourcesOnly,
          readOnly: widget.readOnly);
      if (!mounted || request != generation || key != _contextKey) {
        next.dispose();
        return;
      }
      final old = thumbnail, oldController = thumbnailController;
      setState(() {
        thumbnail = next;
        _thumbnailKey = key;
        thumbnailController = TicketLayoutController(next.template);
      });
      old?.dispose();
      oldController?.dispose();
    });
  }

  StreamSubscription? _authChanges;
  void _contextChanged() {
    if (!mounted) return;
    // Inline previews have no PDF thumbnail, but must still discard a previous
    // identity/context's response and reauthorize through the preview endpoint.
    setState(() {});
    if (thumbnail == null) return;
    if (!thumbnail!.isValid) {
      generation++;
      setState(() {
        thumbnail?.dispose();
        thumbnail = null;
        _thumbnailKey = null;
      });
    }
    if (widget.showPreview && !_editorOpen && _thumbnailKey != _contextKey)
      unawaited(refresh());
  }

  bool _editorOpen = false;
  bool _restoredPanel = false;
  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final root =
        context.findAncestorWidgetOfExactType<RouterScope>()?.controller.root;
    final panel = root == null
        ? null
        : Uri.parse(root.currentUrl).queryParameters['panel'];
    if (!_restoredPanel &&
        !_editorOpen &&
        widget.feature.layout != null &&
        MediaQuery.sizeOf(context).width < 900 &&
        (panel == 'elements' || panel == 'properties')) {
      _restoredPanel = true;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) edit();
      });
    }
  }

  Future<void> edit() async {
    if (busy || unsupported || widget.readOnly || _editorOpen) return;
    _editorOpen = true;
    _refresh(() => busy = true);
    try {
      await ExceptionHandler.guard(context, futureFunction: () async {
        if (_loading != null) await _loading;
        if (thumbnail == null || _thumbnailKey != _contextKey) await refresh();
        if (thumbnail == null || _thumbnailKey != _contextKey) return;
        final r = thumbnail!.clone();
        if (!mounted) {
          r.dispose();
          return;
        }
        final showTemplatePicker = await service.openTemplatePickerOnce(
            widget.occasionId, RightsService.currentUser()?.id ?? 'editor',
            configured: widget.feature.layout?['templates']?[type] != null ||
                (widget.feature.ticketBackground?.isNotEmpty ?? false));
        if (!mounted) {
          r.dispose();
          return;
        }
        final initialTemplate = jsonEncode(r.template.toJson());
        final initialBackground = widget.feature.ticketBackground;
        // Loading the editor and refreshing its thumbnail are separate operations.
        _refresh(() => busy = false);
        final routeRouter = context
            .findAncestorWidgetOfExactType<RouterScope>()
            ?.controller
            .root;
        final result = await showDialog<TicketLayoutResult>(
            context: context,
            useSafeArea: false,
            builder: (c) => AppDialog.fullscreen(
                child: TicketLayoutEditor(
                    routeRouter: routeRouter,
                    productEditing: widget.productEditing,
                    showTemplatePicker: showTemplatePicker,
                    onSave: widget.onSave == null
                        ? null
                        : (result) async {
                            final draft =
                                TicketFeature.fromJson(widget.feature.toJson());
                            draft.ticketType = type;
                            draft.ticketBackground = result.background;
                            draft.layout = ticketLayoutDocument({
                              'schemaVersion': 3,
                              'templates': {
                                ...?(widget.feature.layout?['templates']
                                    as Map?),
                                type: result.template.toJson(),
                              }
                            });
                            await widget.onSave!(draft);
                          },
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
          _refresh(() {
            widget.feature.ticketType = type;
            widget.feature.layout = ticketLayoutDocument({
              'schemaVersion': 3,
              'templates': {
                ...?(widget.feature.layout?['templates'] as Map?),
                type: result.template.toJson()
              }
            });
            widget.feature.ticketBackground = result.background;
            if (widget.onSave != null) widget.feature.markLayoutSaved();
          });
          if (jsonEncode(result.template.toJson()) != initialTemplate ||
              result.background != initialBackground) {
            if (widget.showPreview) unawaited(refresh());
          }
        }
      });
    } finally {
      _editorOpen = false;
      if (mounted && widget.showPreview && _thumbnailKey != _contextKey)
        unawaited(refresh());
      final root =
          context.findAncestorWidgetOfExactType<RouterScope>()?.controller.root;
      if (root != null && mounted)
        await DayRouteSelection.write(root, 'panel', null, replace: true);
    }
    if (mounted) _refresh(() => busy = false);
  }

  Widget _previewCanvas() => CustomPaint(
      size: thumbnail!.template.area.size,
      painter: TicketLayoutPainter(thumbnailController!, thumbnail!,
          thumbnail!.previewData(thumbnailController!.document, 'normal'),
          cropToTicket: true));

  @override
  Widget build(BuildContext context) =>
      Column(crossAxisAlignment: CrossAxisAlignment.center, children: [
        if (widget.showDeliverySelector) ...[
          TicketDeliverySelector(
              value: widget.feature.deliveryMode,
              enabled: widget.feature.isEnabled && !widget.readOnly,
              onChanged: (mode) {
                _refresh(() => widget.feature.deliveryMode = mode);
                if (mode.includesPdf && widget.showPreview) refresh();
              }),
          const SizedBox(height: 4),
          if (widget.feature.isEnabled && widget.occasionId > 0)
            TicketDeliveryPreview(
                revision: jsonEncode([
                  TicketLayoutService.identityKey(),
                  widget.occasionId,
                  RightsService.currentOccasion()?.aggregateVersion
                ]),
                mode: widget.feature.deliveryMode,
                load: () async {
                  final data = await Supabase.instance.client
                      .rpc('get_occasion_setup_email_preview', params: {
                    'p_id': null,
                    'p_expected_revision': null,
                    'p_message_type': 'order_tickets',
                    'p_occasion': widget.occasionId,
                    'p_delivery_mode': null,
                  });
                  return Map<String, dynamic>.from(data as Map);
                }),
          const SizedBox(height: 16),
        ],
        CheckboxListTile(
            value: widget.feature.pregeneratedTickets,
            title: Text(FeaturesStrings.enablePregeneratedTickets),
            subtitle: Text(FeaturesStrings.pregeneratedTicketsDescription),
            onChanged: widget.readOnly
                ? null
                : (v) => _refresh(
                    () => widget.feature.pregeneratedTickets = v ?? false)),
        if (widget.showScanningSettings) ...[
          TicketScanningSettings(
              feature: widget.feature, readOnly: widget.readOnly),
          const SizedBox(height: 12),
        ],
        if (widget.feature.deliveryMode.includesPdf && unsupported)
          Text(TicketLayoutStrings.unsupported),
        if (widget.feature.deliveryMode.includesPdf &&
            thumbnail?.missingBackground == true)
          Padding(
              padding: const EdgeInsets.all(12),
              child: Text(TicketLayoutStrings.missingBackground)),
        if (widget.feature.deliveryMode.includesPdf &&
            widget.showPreview &&
            thumbnail != null &&
            !unsupported)
          InkWell(
              onTap: () => showDialog<void>(
                  context: context,
                  builder: (c) => AppDialog.fullscreen(
                      child: Scaffold(
                          appBar: AppDialogAppBar(
                              title: Text(TicketLayoutStrings.pdf),
                              onClose: () => Navigator.pop(c)),
                          body: InteractiveViewer(
                              minScale: .5,
                              maxScale: 4,
                              child: Center(
                                  child: FittedBox(
                                      fit: BoxFit.contain,
                                      child: _previewCanvas())))))),
              child: SizedBox(
                  height: 200,
                  child:
                      FittedBox(fit: BoxFit.contain, child: _previewCanvas()))),
        const SizedBox(height: 8),
        if (!widget.readOnly && widget.feature.conflictDraft != null)
          TextButton(
              onPressed: () {
                _refresh(() => widget.feature.restoreConflictDraft());
                refresh();
              },
              child: Text(TicketLayoutStrings.restoreDraft)),
        FilledButton.icon(
            onPressed: busy ||
                    unsupported ||
                    widget.readOnly ||
                    !(widget.service.setupDraftId != null
                        ? RightsService.currentUnit()?.id ==
                                widget.service.setupUnitId &&
                            RightsService.hasCapability(
                                AuthorizationCapabilities.occasionsCreate)
                        : RightsService.hasCapability(
                            AuthorizationCapabilities.ticketLayoutsWrite))
                ? null
                : edit,
            icon: busy
                ? const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2))
                : const Icon(Icons.edit_outlined),
            label: Text(widget.feature.deliveryMode.includesPdf
                ? TicketLayoutStrings.edit
                : TicketDeliveryStrings.text('editPrintPdf'))),
      ]);
}
