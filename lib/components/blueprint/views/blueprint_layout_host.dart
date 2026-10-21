import 'blueprint_standing_capacity_control.dart';
import 'blueprint_layout_help.dart';
import 'package:fstapp/services/dialog_helper.dart';
import '../blueprint_seat_state.dart';
import 'package:fstapp/components/eshop/db_tickets.dart';
import 'package:fstapp/components/eshop/models/ticket_model.dart';
import 'package:fstapp/components/eshop/models/order_model.dart';
import 'package:fstapp/components/eshop/order_item_strings.dart';
import 'package:fstapp/components/eshop/ticket_cancellation_updates.dart';
import 'package:fstapp/components/single_data_grid/data_grid_action_confirmation.dart';
import '../blueprint_text_preparation.dart';
import 'dart:async';
import 'dart:convert';
import 'package:http/http.dart' as http;
import 'blueprint_plan_editor.dart';
import 'package:festapp_core/eshop.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:fstapp/components/_shared/common_strings.dart';
import 'package:fstapp/components/_shared/editor_action_bar.dart';
import 'package:fstapp/data_services/rights_service.dart';
import 'package:fstapp/components/eshop/db_eshop.dart';
import 'package:fstapp/services/toast_helper.dart';
import 'package:fstapp/services/utilities_all.dart';
import 'package:fstapp/widgets/app_dialog.dart';
import 'package:fstapp/theme_config.dart';
import 'package:venue_seat_picker/venue_seat_picker.dart';
import '../blueprint_layout_contract.dart';
import '../blueprint_group_binding.dart';
import '../blueprint_layout_resources.dart';
import '../blueprint_layout_controller.dart';
import '../blueprint_model.dart';
import '../blueprint_strings.dart';
import 'blueprint_create_order_dialog.dart';
import 'blueprint_layout_legend.dart';
import 'blueprint_editor_feedback.dart';
import 'blueprint_product_dialogs.dart';

enum _BlueprintScreenMode { reservations, edit }

/// Business UI surrounds the public editor; geometry and its history remain in
/// the package, while all prices, rights and commands remain in Festapp.
class BlueprintLayoutHost extends StatefulWidget {
  const BlueprintLayoutHost(
      {super.key,
      required this.source,
      required this.reload,
      this.loadTextResources,
      this.assetResolver});
  final BlueprintModel source;
  final Future<BlueprintTextResources> Function()? loadTextResources;
  final BlueprintLayoutAssetResolver? assetResolver;
  final Future<BlueprintModel?> Function() reload;
  @override
  State<BlueprintLayoutHost> createState() => _BlueprintLayoutHostState();
}

class _BlueprintLayoutHostState extends State<BlueprintLayoutHost> {
  late BlueprintLayoutController controller;
  final _hostFocus = FocusNode(debugLabel: 'Blueprint host actions');
  late _BlueprintScreenMode _screenMode;
  Set<String> _commercialSelection = {};
  final Map<String, GlobalKey> _commercialRowKeys = {};
  bool _showIndividualCommercialSeats = false;
  bool get _editingPlan => _screenMode == _BlueprintScreenMode.edit;
  String? _message;
  BlueprintSeatState? _legendHover;
  late final _assets = widget.assetResolver ?? BlueprintLayoutAssetResolver();
  bool _assetsPending = false;
  bool _assetsFailed = false;
  bool _operationPending = false;
  Future<void>? _modeFlight;
  int _assetGeneration = 0;
  Future<BlueprintTextResources>? _fontCatalog;
  // Viewing uses persisted outlines; even the editor catalog loads only on demand.
  Future<BlueprintTextResources> get _fonts =>
      _fontCatalog ??= widget.loadTextResources?.call() ??
          BlueprintTextResources.load(controller.snapshot.occasionId);
  bool get _canEdit => RightsService.canEditOccasion();
  bool get _canOrder => RightsService.canUpdateOrders();
  bool get _busy =>
      controller.isBusy ||
      _operationPending ||
      _assetsPending ||
      _modeFlight != null;

  @override
  void initState() {
    super.initState();
    controller = BlueprintLayoutController(source: widget.source);
    controller.layout.readOnly = !_canEdit;
    RightsService.occasionLinkModelNotifier.addListener(_rightsChanged);
    // Decide once on entry. Inserting or saving never leaves explicit editing.
    _screenMode = _canEdit && controller.layout.document.nodes.isEmpty
        ? _BlueprintScreenMode.edit
        : _BlueprintScreenMode.reservations;
    _loadAssets();
  }

  void _rightsChanged() {
    if (!mounted) return;
    setState(() {
      controller.layout.readOnly = !_canEdit;
      if (!_canOrder) controller.setMode(BlueprintLayoutMode.manage);
    });
  }

  @override
  void dispose() {
    RightsService.occasionLinkModelNotifier.removeListener(_rightsChanged);
    _assets.dispose();
    _hostFocus.dispose();
    controller.dispose();
    super.dispose();
  }

  Future<void> _setScreenMode(_BlueprintScreenMode mode) {
    if (_modeFlight != null) return _modeFlight!;
    if (_busy ||
        mode == _screenMode ||
        (mode == _BlueprintScreenMode.edit && !_canEdit)) {
      return Future.value();
    }
    if (!_editingPlan) {
      _applyScreenMode(mode);
      return Future.value();
    }
    final session = controller;
    final flight = _finishScreenMode(session, mode);
    setState(() {
      _message = null;
      _modeFlight = flight;
    });
    return flight;
  }

  Future<void> _finishScreenMode(
      BlueprintLayoutController session, _BlueprintScreenMode mode) async {
    try {
      await finishBlueprintTextEditing();
      if (!mounted || !identical(session, controller)) return;
      final document = session.layout.document;
      if (!session.validatePlacementForReservations()) {
        throw StateError('layout_placement_invalid');
      }
      final issues =
          compileScene(document, resources: session.layout.resources)['issues']
              as List;
      if (issues.any((issue) => const {
            'text_layout_unavailable',
            'font_family_unavailable',
            'font_face_unavailable'
          }.contains(issue['reason']))) {
        final provider = await _fonts;
        if (!mounted || !identical(session, controller)) return;
        final result = await BlueprintTextPreparation(provider.prepareTextBatch)
            .prepare(
                document,
                {
                  for (final family in provider.families)
                    family['id'] as String: family
                },
                session.layout.resources,
                stillCurrent: () =>
                    mounted &&
                    identical(session, controller) &&
                    identical(document, session.layout.document));
        if (!mounted || !identical(session, controller)) return;
        if (result is BlueprintTextSuperseded) {
          throw StateError(BlueprintStrings.draftChanged);
        }
        if (result is BlueprintTextFailed) throw result.error;
        if (!commitBlueprintTextResources(
            session.layout, (result as BlueprintTextReady).resources)) {
          throw StateError('invalid_layout_resources');
        }
      }
      if (!identical(document, session.layout.document)) {
        throw StateError(BlueprintStrings.draftChanged);
      }
      if ((compileScene(document, resources: session.layout.resources)['issues']
              as List)
          .isNotEmpty) {
        throw StateError('invalid_layout_resources');
      }
      _applyScreenMode(mode);
    } catch (error) {
      if (mounted && identical(session, controller)) {
        setState(() => _message = BlueprintStrings.layoutErrorMessage(error));
      }
    } finally {
      if (mounted && identical(session, controller)) {
        setState(() => _modeFlight = null);
      }
    }
  }

  void _editFromCanvas(Set<String> selection) {
    if (_editingPlan ||
        !_canEdit ||
        _busy ||
        controller.mode != BlueprintLayoutMode.manage) return;
    _applyScreenMode(_BlueprintScreenMode.edit);
    controller.layout.select({
      for (final node in controller.layout.document.nodes)
        if (selection.contains(node.id)) node.id,
    });
  }

  void _applyScreenMode(_BlueprintScreenMode mode) {
    controller.layout.cancelGesture();
    controller.layout.select({});
    controller.setMode(BlueprintLayoutMode.manage);
    setState(() {
      _screenMode = mode;
      _legendHover = null;
      _message = null;
    });
    _hostFocus.requestFocus();
  }

  KeyEventResult _hostHistoryKey(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent ||
        !_editingPlan ||
        !_canEdit ||
        _busy ||
        controller.layout.readOnly ||
        controller.layout.saving ||
        ModalRoute.of(context)?.isCurrent == false) {
      return KeyEventResult.ignored;
    }
    final focused = FocusManager.instance.primaryFocus?.context;
    if (focused?.widget is EditableText ||
        focused?.findAncestorStateOfType<EditableTextState>() != null) {
      return KeyEventResult.ignored;
    }
    final keyboard = HardwareKeyboard.instance;
    if (!keyboard.isControlPressed && !keyboard.isMetaPressed) {
      return KeyEventResult.ignored;
    }
    if (event.logicalKey == LogicalKeyboardKey.keyZ) {
      keyboard.isShiftPressed
          ? controller.layout.redo()
          : controller.layout.undo();
    } else if (event.logicalKey == LogicalKeyboardKey.keyY) {
      controller.layout.redo();
    } else {
      return KeyEventResult.ignored;
    }
    return KeyEventResult.handled;
  }

  void _startOperation(BlueprintLayoutMode mode) {
    if (_busy || _editingPlan || !_canOrder) return;
    final selected = Set<String>.from(_detailSeatIds);
    if (mode == BlueprintLayoutMode.order) {
      for (final unit in controller.layout.document.selectionUnits) {
        final members = Set<String>.from(unit['nodeIds'] as List);
        if (members.any(selected.contains)) selected.addAll(members);
      }
    }
    controller.setMode(mode);
    final eligible = selected.where((id) {
      final seat = controller.snapshot.seatBindings[id];
      if (seat?.spotId == null || seat!.blocked) return false;
      return mode != BlueprintLayoutMode.order ||
          (!controller.isProtected(id) &&
              controller.adapter.product(seat)?.price != null);
    }).toList();
    // A swap never silently picks two seats from a larger selection.
    if (mode != BlueprintLayoutMode.swap || eligible.length <= 2) {
      for (final id in eligible) {
        if (controller.operationSelection.contains(id)) continue;
        if (mode == BlueprintLayoutMode.order) {
          final unit = controller.layout.document.selectionUnits
              .where((u) => (u['nodeIds'] as List? ?? const []).contains(id))
              .firstOrNull;
          if (unit != null &&
              (unit['nodeIds'] as List)
                  .any((member) => !eligible.contains(member))) continue;
        }
        controller.activateNode(id);
      }
    }
    // Semantics activation need not focus the button. Keep Escape available
    // even when the new operation replaces that button before any canvas click.
    _hostFocus.requestFocus();
  }

  void _cancelOperation() {
    if (_busy) return;
    controller.setMode(BlueprintLayoutMode.manage);
    _hostFocus.requestFocus();
  }

  Future<void> _loadAssets() async {
    final session = controller;
    final generation = ++_assetGeneration;
    final requested = session.layout.resources;
    bool current() =>
        mounted &&
        identical(session, controller) &&
        generation == _assetGeneration;
    setState(() {
      _assetsPending = true;
      _assetsFailed = false;
    });
    try {
      final resources = await _assets.resolve(requested);
      if (!current()) return;
      if (!commitBlueprintImages(session.layout,
          requestedResources: requested, resolvedResources: resources)) {
        throw StateError('invalid_layout_resources');
      }
    } catch (error) {
      if (current())
        setState(() {
          _message = error.toString();
          _assetsFailed = true;
        });
    } finally {
      if (current()) setState(() => _assetsPending = false);
    }
  }

  Future<void> _run(Future<void> Function() action) async {
    if (_busy) return;
    setState(() => _message = null);
    try {
      await action();
    } catch (error) {
      if (mounted) {
        setState(() => _message = BlueprintStrings.layoutErrorMessage(error));
      }
    } finally {
      if (mounted) setState(() {});
    }
  }

  Future<void>? _saveFlight;
  Future<void> _save() {
    if (_saveFlight != null) return _saveFlight!;
    final future = _saveCaptured().whenComplete(() => _saveFlight = null);
    _saveFlight = future;
    return future;
  }

  Future<void> _saveCaptured() async {
    if (!_canEdit) return;
    await finishBlueprintTextEditing();
    if (!mounted || !_canEdit) return;
    if (controller.saver.pending == null &&
        !controller.validatePlacementForReservations()) {
      throw StateError('layout_placement_invalid');
    }
    BlueprintLayoutSnapshot? captured;
    Map<String, int>? capturedAreas;
    Map<String, dynamic>? prepared;
    if (controller.saver.pending == null) {
      if (controller.layout.document.schemaVersion == 2) {
        final session = controller;
        captured = session.snapshot;
        capturedAreas = session.areaCapacities;
        final resources = session.layout.resources;
        final provider = await _fonts;
        prepared = await BlueprintTextPreparation(provider.prepareTextBatch)
            .prepareSnapshot(
                captured.document,
                {for (final f in provider.families) f['id'] as String: f},
                resources);
        if (!mounted || !identical(session, controller)) return;
        if (identical(controller.layout.document, captured.document) &&
            !commitBlueprintTextResources(controller.layout, prepared))
          throw StateError('invalid_layout_resources');
      } else {
        throw const FormatException('canonical_document_required');
      }
    }
    controller.layout.readOnly = !_canEdit;
    if (!_canEdit) return;
    final result = await controller.save(
        captured: captured,
        capturedAreaCapacities: capturedAreas,
        preparedResources: prepared);
    if (!mounted) return;
    if (result.accepted) {
      ToastHelper.Show(context, CommonStrings.saved,
          severity: ToastSeverity.Ok);
      return;
    }
    setState(() => _message = [
          result.reason ?? BlueprintStrings.saveConflict,
          ...result.issues
              .map((i) => '${i.nodeId ?? i.spotId ?? ""}: ${i.reason}')
        ].join('\n'));
    await showDialog<void>(
        context: context,
        builder: (dialogContext) => AppAlertDialog(
              title: Text(BlueprintStrings.saveConflict),
              content: Text(_message!),
              actions: [
                TextButton(
                    onPressed: () async {
                      await Clipboard.setData(ClipboardData(
                          text: jsonEncode(controller.snapshot.toJson())));
                      if (dialogContext.mounted) Navigator.pop(dialogContext);
                    },
                    child: Text(BlueprintStrings.copyDraft)),
                TextButton(
                    onPressed: () => Navigator.pop(dialogContext),
                    child: Text(CommonStrings.keepEditing)),
                FilledButton(
                    onPressed: () async {
                      final source = await widget.reload();
                      if (!mounted || source?.layoutSnapshot == null) return;
                      final old = controller;
                      setState(() {
                        controller = BlueprintLayoutController(source: source!);
                        controller.layout.readOnly = !_canEdit;
                        _modeFlight = null;
                        _fontCatalog = null;
                        _message = null;
                      });
                      old.dispose();
                      await _loadAssets();
                      if (dialogContext.mounted) Navigator.pop(dialogContext);
                    },
                    child: Text(BlueprintStrings.reloadSaved)),
              ],
            ));
  }

  Future<void> _refresh() async {
    final source = await widget.reload();
    if (mounted && source != null) controller.refreshLive(source);
  }

  Future<void> _order() async {
    if (!_canOrder || _busy || controller.selectedSpotIds.isEmpty) return;
    setState(() => _operationPending = true);
    try {
      final selected = List<int>.of(controller.selectedSpotIds);
      final analysis = await DbEshop.analyzeNewOrderSpots(selected);
      if (!mounted) return;
      final done = await showDialog<bool>(
          context: context,
          barrierDismissible: false,
          builder: (_) => BlueprintCreateOrderDialog(
              selectedSpotIds: selected, initialAnalysis: analysis));
      if (done == true) {
        await _refresh();
        if (mounted) controller.setMode(BlueprintLayoutMode.manage);
      }
    } finally {
      if (mounted) setState(() => _operationPending = false);
    }
  }

  Future<void> _swap() async {
    if (!_canOrder || _busy || controller.selectedSpotIds.length != 2) return;
    setState(() {
      _operationPending = true;
      _message = null;
    });
    try {
      final preview = await controller.previewSwap();
      if (!mounted) return;
      final sides = (preview['sides'] as List? ?? const []).cast<Map>();
      final orders = (preview['orders'] as List? ?? const []).cast<Map>();
      final confirmed = await showDialog<bool>(
          context: context,
          builder: (dialogContext) => AppAlertDialog(
                title: Text(BlueprintStrings.legendSwapSeats),
                content: SizedBox(
                    width: 520,
                    child: SingleChildScrollView(
                        child: Column(
                            mainAxisSize: MainAxisSize.min,
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                          for (final side in sides)
                            ListTile(
                                title: Text('${side['title'] ?? ''}'),
                                subtitle: Text([
                                  if (side['customer'] is Map)
                                    ...[
                                      side['customer']['name'],
                                      side['customer']['surname'],
                                      side['customer']['email']
                                    ].where(
                                        (v) => v != null && '$v'.isNotEmpty),
                                  if (side['ticketId'] != null)
                                    '${BlueprintStrings.ticketLabel}: ${side['ticketId']}',
                                ].join(' '))),
                          for (final order in orders)
                            ListTile(
                                title: Text(
                                    '${BlueprintStrings.orderLabel} ${order['orderId']}'),
                                subtitle: Text(
                                    '${Utilities.formatPrice(context, (order['beforeAmount'] as num).toDouble(), currencyCode: order['currencyCode'] as String?)} → '
                                    '${Utilities.formatPrice(context, (order['afterAmount'] as num).toDouble(), currencyCode: order['currencyCode'] as String?)}'),
                                trailing: Text(Utilities.formatPrice(
                                    context, (order['delta'] as num).toDouble(),
                                    currencyCode:
                                        order['currencyCode'] as String?))),
                          Text(BlueprintStrings.swapServerNotice),
                        ]))),
                actions: [
                  TextButton(
                      onPressed: () => Navigator.pop(dialogContext, false),
                      child: Text(CommonStrings.storno)),
                  FilledButton(
                      onPressed: () => Navigator.pop(dialogContext, true),
                      child: Text(BlueprintStrings.legendSwapSeats))
                ],
              ));
      if (confirmed == true && mounted && _canOrder) {
        await controller.swapSelected();
        await _refresh();
        if (mounted) controller.setMode(BlueprintLayoutMode.manage);
      }
    } catch (error) {
      if (mounted)
        setState(() => _message =
            error is http.ClientException || error is TimeoutException
                ? BlueprintStrings.operationNetworkError
                : error.toString());
    } finally {
      if (mounted) setState(() => _operationPending = false);
    }
  }

  String _productText(int? id) {
    final p = controller.products[id];
    if (p == null) return BlueprintStrings.noProductAssigned;
    final price = p.price;
    return '${p.title ?? ""}${price == null ? "" : " (${Utilities.formatPrice(context, price, currencyCode: p.currencyCode)})"}';
  }

  Future<void> _product(String nodeId,
      {bool group = false, bool freeOnly = false}) async {
    final picked = await showDialog<ProductModel>(
        context: context,
        builder: (_) => SelectProductDialog.catalog(
            products: controller.products.values.toList(),
            onProductSaved: controller.upsertCatalogProduct,
            currentProductId: group
                ? controller.snapshot.groupProducts[nodeId]
                : controller.effectiveProductId(nodeId),
            affectedSeatCount: (id) => controller.snapshot.seatBindings.values
                .where((s) => s.productId == id)
                .length));
    if (picked == null || !mounted) return;
    await _run(() async {
      if (group) {
        controller.applyGroupProduct(nodeId, picked.id!,
            freeOnly: freeOnly, replaceOverrides: true);
      } else {
        controller.assignSeatProduct(nodeId, picked.id!);
      }
    });
  }

  Future<void> _bulkProduct() async {
    final groups = _selectedCommercialGroups;
    final ids = {
      for (final seat in controller.snapshot.seatBindings.values)
        if (groups.contains(seat.groupNodeId) ||
            _commercialSelection.contains(seat.nodeId))
          seat.nodeId,
    };
    final blockers = ids.where(controller.isProtected).length;
    var freeOnly = false;
    if (blockers > 0) {
      final choice = await showDialog<bool>(
          context: context,
          builder: (dialogContext) => AppAlertDialog(
                title: Text(BlueprintStrings.selectProduct),
                content: Text(
                    '${BlueprintStrings.selectedCount(ids.length)}\n${BlueprintStrings.protectedCount(blockers)}'),
                actions: [
                  TextButton(
                      onPressed: () => Navigator.pop(dialogContext),
                      child: Text(CommonStrings.storno)),
                  FilledButton(
                      onPressed: () => Navigator.pop(dialogContext, true),
                      child: Text(BlueprintStrings.onlyFreeSeats))
                ],
              ));
      if (choice != true || !mounted) return;
      freeOnly = true;
    }
    final product = await showDialog<ProductModel>(
        context: context,
        builder: (_) => SelectProductDialog.catalog(
            products: controller.products.values.toList(),
            onProductSaved: controller.upsertCatalogProduct,
            affectedSeatCount: (id) => controller.snapshot.seatBindings.values
                .where((s) => s.productId == id)
                .length));
    if (product != null && mounted)
      await _run(() async {
        if (groups.isNotEmpty) {
          controller.applyGroupsProduct(groups, product.id!,
              freeOnly: freeOnly,
              replaceOverrides: true,
              additionalSeatIds: _commercialSelection
                  .where(controller.snapshot.seatBindings.containsKey)
                  .toSet());
        } else {
          controller.assignProducts(ids, product.id!, freeOnly: freeOnly);
        }
      });
  }

  Widget _inspector(BuildContext context, LayoutNode node) {
    final snapshot = controller.snapshot;
    final binding = snapshot.seatBindings[node.id];

    final commercialGroupId = binding?.groupNodeId ??
        (node.kind == 'table'
            ? blueprintCommercialGroupFor(node, controller.layout.document,
                groupProducts: snapshot.groupProducts)
            : null) ??
        node.id;
    final commercialGroup = controller.layout.document.nodes
        .where((candidate) => candidate.id == commercialGroupId)
        .firstOrNull;
    final members = snapshot.seatBindings.values
        .where((s) => s.groupNodeId == commercialGroupId)
        .toList();
    final isGroup = binding == null;
    if (isGroup &&
        !const {'table', 'group', 'row', 'section'}.contains(node.kind) &&
        members.isEmpty) return const SizedBox.shrink();
    final blockers =
        members.where((s) => controller.isProtected(s.nodeId)).length;
    final products = members.map((s) => s.productId).toSet();
    final protected = binding != null && controller.isProtected(node.id);
    final defaultId = snapshot.groupProducts[commercialGroupId];
    return Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(children: [
              Expanded(
                  child: Text(
                      binding?.title ?? commercialGroup?.label ?? node.label,
                      style: Theme.of(context).textTheme.titleMedium)),
              if (_canEdit)
                IconButton(
                    tooltip: CommonStrings.rename,
                    key: ValueKey(
                        'rename-commercial-${binding != null ? node.id : commercialGroupId}'),
                    onPressed: _busy || protected
                        ? null
                        : () => _renameCommercial(
                            binding != null ? node : commercialGroup ?? node),
                    icon: const Icon(Icons.edit_outlined, size: 18)),
            ]),
            const SizedBox(height: 8),
            Text(isGroup && products.length > 1
                ? BlueprintStrings.mixedProducts
                : _productText(binding?.productId ??
                    (isGroup && products.length == 1
                        ? products.first
                        : defaultId))),
            if (isGroup)
              Text(
                  '${BlueprintStrings.groupDefault}: ${_productText(defaultId)}'),
            if (isGroup) Text(BlueprintStrings.seatCount(members.length)),
            if (isGroup)
              Text(BlueprintStrings.defaultProductHint,
                  style: Theme.of(context).textTheme.bodySmall),
            if (isGroup && members.isEmpty) Text(BlueprintStrings.emptyGroup),
            if (protected)
              Text(BlueprintStrings.seatState(
                  controller.adapter.state(binding).name)),
            if (isGroup && blockers > 0)
              Semantics(
                  liveRegion: true,
                  child: Text(
                      BlueprintStrings.protectedCount(protected ? 1 : blockers),
                      style: TextStyle(
                          color: Theme.of(context).colorScheme.error))),
            if (binding != null &&
                _canOrder &&
                controller.adapter.spots[binding.spotId] != null)
              ExpansionTile(
                  tilePadding: EdgeInsets.zero,
                  title: Text(BlueprintStrings.ticketLabel),
                  children: [
                    SelectableText(controller.adapter.spots[binding.spotId]!
                        .blueprintTooltip(context))
                  ]),
            if (_canEdit && !protected) ...[
              if (binding != null &&
                  defaultId != null &&
                  binding.productId != defaultId)
                TextButton(
                    key: const ValueKey('restore-table-product'),
                    onPressed: _busy || protected
                        ? null
                        : () => _run(() async =>
                            controller.assignSeatProduct(node.id, defaultId)),
                    child: Text(BlueprintStrings.useTableDefault)),
              TextButton.icon(
                  onPressed: _busy || protected || (isGroup && blockers > 0)
                      ? null
                      : () => _product(isGroup ? commercialGroupId : node.id,
                          group: isGroup),
                  icon: const Icon(Icons.sell_outlined),
                  label: Text(isGroup
                      ? BlueprintStrings.assignProductToGroup
                      : BlueprintStrings.selectProduct)),
              if (isGroup && blockers > 0)
                TextButton(
                    onPressed: _busy
                        ? null
                        : () => _product(commercialGroupId,
                            group: true, freeOnly: true),
                    child: Text(BlueprintStrings.onlyFreeSeats)),
              if (binding != null)
                SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    title: Text(BlueprintStrings.blockSeat),
                    value: binding.blocked,
                    onChanged: _busy || protected
                        ? null
                        : (value) => _run(
                            () async => controller.setBlocked(node.id, value))),
            ],
            if (isGroup && members.isNotEmpty)
              ExpansionTile(
                  tilePadding: EdgeInsets.zero,
                  title: Text(BlueprintStrings.individualAssignments),
                  children: [
                    for (final seat in members)
                      ListTile(
                          title: Text(seat.title),
                          subtitle: Text(_productText(seat.productId)),
                          selected: _commercialSelection.contains(seat.nodeId),
                          onTap: _busy
                              ? null
                              : () => _setCommercialSelection({seat.nodeId}))
                  ]),
          ],
        ));
  }

  String _commercialId(LayoutNode node) {
    final snapshot = controller.snapshot;
    if (snapshot.groupProducts.containsKey(node.id) ||
        snapshot.seatBindings.values.any((seat) => seat.groupNodeId == node.id))
      return node.id;
    return blueprintCommercialGroupFor(node, controller.layout.document,
            groupProducts: snapshot.groupProducts) ??
        node.id;
  }

  Map<String, LayoutNode> get _commercialTables {
    final nodes = {for (final n in controller.layout.document.nodes) n.id: n};
    final ids = {
      ...controller.snapshot.groupProducts.keys,
      ...controller.snapshot.seatBindings.values
          .map((seat) => seat.groupNodeId)
          .whereType<String>(),
      for (final n in nodes.values)
        if (n.kind == 'table') _commercialId(n),
    };
    final tables = [
      for (final id in ids)
        if (nodes[id] != null) nodes[id]!
    ]..sort((a, b) => Utilities.naturalCompare(a.label, b.label));
    return {for (final n in tables) n.id: n};
  }

  Set<String> get _selectedCommercialGroups => {
        for (final id in _commercialSelection)
          if (_commercialTables.containsKey(id)) id,
      };

  String _viewSelectionTarget(String id) {
    final node =
        controller.layout.document.nodes.where((n) => n.id == id).firstOrNull;
    return node?.kind == 'table' ? _commercialId(node!) : id;
  }

  void _setCommercialSelection(Set<String> selection) {
    if (_busy || controller.mode != BlueprintLayoutMode.manage) return;
    final nodes = {for (final n in controller.layout.document.nodes) n.id};
    setState(() => _commercialSelection = {
          for (final id in selection)
            if (nodes.contains(id)) _viewSelectionTarget(id),
        });
    setState(() {});
  }

  void _selectCommercialRow(String id) {
    final next = HardwareKeyboard.instance.isShiftPressed
        ? {..._commercialSelection}
        : <String>{};
    if (!next.add(id)) next.remove(id);
    _setCommercialSelection(next);
  }

  void _selectCommercialFromCanvas(Set<String> selection) {
    if (_editingPlan || _busy || controller.mode != BlueprintLayoutMode.manage)
      return;
    _setCommercialSelection(selection);
    final selectedId =
        _commercialSelection.length == 1 ? _commercialSelection.single : null;
    final tableId = selectedId == null
        ? null
        : controller.snapshot.seatBindings[selectedId]?.groupNodeId ??
            selectedId;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted ||
          _editingPlan ||
          controller.mode != BlueprintLayoutMode.manage) return;
      if (selectedId != null && !_commercialSelection.contains(selectedId))
        return;
      final rowContext = _commercialRowKeys[tableId]?.currentContext;
      if (rowContext != null) {
        // Reveal only inside the table list. The static helper also scrolls
        // ancestor viewports, including the administration tab's PageView.
        Scrollable.of(rowContext).position.ensureVisible(
              rowContext.findRenderObject()!,
              alignment: .5,
            );
      }
    });
  }

  Future<void> _renameCommercial(LayoutNode node) async {
    var name = controller.snapshot.seatBindings[node.id]?.title ?? node.label;
    final value = await showDialog<String>(
        context: context,
        builder: (dialogContext) => AppAlertDialog(
              title: Text(CommonStrings.rename),
              content: TextFormField(
                  initialValue: name,
                  autofocus: true,
                  onChanged: (value) => name = value,
                  decoration: InputDecoration(labelText: CommonStrings.name),
                  onFieldSubmitted: (value) {
                    if (value.trim().isNotEmpty)
                      Navigator.pop(dialogContext, value);
                  }),
              actions: [
                TextButton(
                    onPressed: () => Navigator.pop(dialogContext),
                    child: Text(CommonStrings.cancel)),
                FilledButton(
                    onPressed: () {
                      if (name.trim().isNotEmpty)
                        Navigator.pop(dialogContext, name);
                    },
                    child: Text(CommonStrings.save)),
              ],
            ));
    if (!mounted || value == null) return;
    await _run(() => _commitCommercialRename(node.id, value));
  }

  void _renameFromInspector(LayoutNode node, String name) {
    if (!_editingPlan || !_canEdit || _busy) {
      throw StateError('blueprint_read_only');
    }
    _run(() => _commitCommercialRename(
        node.kind == 'table' ? _commercialId(node) : node.id, name));
  }

  Future<void> _commitCommercialRename(String nodeId, String name) async {
    final session = controller;
    final before = session.layout.document;
    final next = session.commercialRenameDocument(nodeId, name);
    setState(() => _operationPending = true);
    try {
      final provider = await _fonts;
      final result = await BlueprintTextPreparation(provider.prepareTextBatch)
          .prepare(
              next,
              {for (final f in provider.families) f['id'] as String: f},
              session.layout.resources,
              stillCurrent: () =>
                  mounted &&
                  identical(session, controller) &&
                  identical(before, session.layout.document));
      if (!mounted || !identical(session, controller)) return;
      if (result is BlueprintTextSuperseded) {
        throw StateError(BlueprintStrings.draftChanged);
      }
      if (result is BlueprintTextFailed) throw result.error;
      session.renameCommercialNode(nodeId, name,
          preparedResources: (result as BlueprintTextReady).resources);
    } finally {
      if (mounted) setState(() => _operationPending = false);
    }
  }

  Future<void> _editAreaProduct(LayoutNode area) async {
    if (!_canEdit || _busy) return;
    final product = controller
        .products[controller.snapshot.areaBindings[area.id]?.productId];
    if (product == null) return;
    final result = await showDialog<Map<String, dynamic>>(
        context: context,
        builder: (_) =>
            EditProductDialog(product: product.copyWith(), isCreating: false));
    if (result == null || !mounted) return;
    await _run(() async {
      setState(() => _operationPending = true);
      try {
        final updated = product.copyWith(
            title: result['title'] as String, price: result['price'] as double);
        final saved = await DbEshop.saveProductBasics(updated);
        if (mounted) controller.upsertCatalogProduct(saved);
      } finally {
        if (mounted) setState(() => _operationPending = false);
      }
    });
  }

  Widget _areaDetail(LayoutNode area) {
    final availability = controller.adapter.areaAvailability[area.id];
    final capacity = controller.areaCapacity(area.id);
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Row(children: [
        Expanded(
            child: Text(area.label,
                style: Theme.of(context).textTheme.titleMedium)),
        if (_canEdit)
          IconButton(
              tooltip: CommonStrings.rename,
              onPressed: _busy ? null : () => _renameCommercial(area),
              icon: const Icon(Icons.edit_outlined, size: 18)),
      ]),
      Text(_productText(controller.snapshot.areaBindings[area.id]?.productId)),
      const SizedBox(height: 12),
      Text(BlueprintStrings.standingAvailability(
          (availability?['available'] as num?)?.toInt() ?? 0,
          (availability?['capacity'] as num?)?.toInt() ?? capacity)),
      if (_canEdit &&
          controller.snapshot.areaBindings.containsKey(area.id)) ...[
        const SizedBox(height: 16),
        BlueprintStandingCapacityControl(
            controller: controller, nodeId: area.id, enabled: !_busy),
      ],
      if (_canEdit &&
          controller.products.containsKey(
              controller.snapshot.areaBindings[area.id]?.productId))
        TextButton.icon(
            key: const ValueKey('commercial-area-product'),
            onPressed: _busy ? null : () => _editAreaProduct(area),
            icon: const Icon(Icons.sell_outlined, size: 18),
            label: Text(BlueprintStrings.editAreaProduct)),
    ]);
  }

  Widget _commercialTableRow(LayoutNode table, bool selected) {
    final members = controller.snapshot.seatBindings.values
        .where((seat) => seat.groupNodeId == table.id)
        .toList();
    final products = members.map((seat) => seat.productId).toSet();
    final summary = products.length > 1
        ? BlueprintStrings.mixedProducts
        : _productText(products.isEmpty
            ? controller.snapshot.groupProducts[table.id]
            : products.single);
    return Padding(
      key: _commercialRowKeys.putIfAbsent(table.id, () => GlobalKey()),
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: MouseRegion(
        onEnter: (_) => controller.layout.highlightObjects(
            {table.id, ...members.map((seat) => seat.nodeId)}),
        onExit: (_) => controller.layout.highlightObjects({}),
        child: Ink(
          decoration: BoxDecoration(
            border: Border.all(
                color: selected
                    ? Theme.of(context).colorScheme.primary
                    : Theme.of(context).dividerColor),
            borderRadius: BorderRadius.circular(8),
            color: selected
                ? Theme.of(context).colorScheme.primary.withValues(alpha: .12)
                : null,
          ),
          child: ListTile(
            key: ValueKey('commercial-table-${table.id}'),
            dense: true,
            contentPadding: const EdgeInsets.symmetric(horizontal: 8),
            minLeadingWidth: 18,
            horizontalTitleGap: 8,
            selected: selected,
            leading: const Icon(Icons.table_restaurant_outlined, size: 18),
            title: Text(table.label.isEmpty
                ? BlueprintStrings.tablesTitle
                : table.label),
            subtitle:
                Text(summary, maxLines: 1, overflow: TextOverflow.ellipsis),
            trailing: Text('(${members.length})',
                style: Theme.of(context).textTheme.bodySmall),
            onTap: _busy ? null : () => _selectCommercialRow(table.id),
          ),
        ),
      ),
    );
  }

  Widget _groupProductDetail(LayoutNode table) {
    final members = controller.snapshot.seatBindings.values
        .where((seat) => seat.groupNodeId == table.id)
        .toList()
      ..sort((a, b) => Utilities.naturalCompare(a.title, b.title));
    final defaultId = controller.snapshot.groupProducts[table.id];
    final mixed = members.any((seat) => seat.productId != defaultId);
    final blockers =
        members.where((seat) => controller.isProtected(seat.nodeId)).length;
    final statusColor = mixed
        ? (ThemeConfig.isDarkMode(context)
            ? Colors.orangeAccent
            : Colors.orange)
        : defaultId == null
            ? Theme.of(context).colorScheme.onSurfaceVariant
            : ThemeConfig.greenColor(context);
    final showSeats = _showIndividualCommercialSeats || mixed;
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Ink(
          decoration: BoxDecoration(
            color: Theme.of(context)
                .colorScheme
                .surfaceContainerHighest
                .withValues(alpha: .3),
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: Theme.of(context).dividerColor),
          ),
          child: ListTile(
            leading: const Icon(Icons.category_outlined),
            title: Text(BlueprintStrings.groupDefaultProduct,
                style: const TextStyle(fontWeight: FontWeight.bold)),
            subtitle: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                    '${BlueprintStrings.currentProductPrefix}${_productText(defaultId)}'),
                const SizedBox(height: 4),
                Row(children: [
                  Icon(
                      mixed
                          ? Icons.warning_amber_rounded
                          : defaultId == null
                              ? Icons.info_outline
                              : Icons.check_circle_outline,
                      size: 14,
                      color: statusColor),
                  const SizedBox(width: 4),
                  Expanded(
                      child: Text(
                          mixed
                              ? BlueprintStrings.statusMixed
                              : defaultId == null
                                  ? BlueprintStrings.noProductAssigned
                                  : BlueprintStrings.statusUniform,
                          style: TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.w500,
                              color: statusColor))),
                ]),
              ],
            ),
            trailing:
                _canEdit ? const Icon(Icons.edit_outlined, size: 20) : null,
            onTap: !_canEdit || _busy || blockers > 0
                ? null
                : () => _product(table.id, group: true),
          ),
        ),
        if (blockers > 0) ...[
          Text(BlueprintStrings.protectedCount(blockers),
              style: TextStyle(color: Theme.of(context).colorScheme.error)),
          if (_canEdit)
            TextButton(
                onPressed: _busy
                    ? null
                    : () => _product(table.id, group: true, freeOnly: true),
                child: Text(BlueprintStrings.onlyFreeSeats)),
        ],
        const SizedBox(height: 12),
        SwitchListTile(
          key: const ValueKey('commercial-individual-seats'),
          contentPadding: EdgeInsets.zero,
          controlAffinity: ListTileControlAffinity.leading,
          title: Text(BlueprintStrings.customizeIndividualSeats),
          value: showSeats,
          onChanged: mixed
              ? null
              : (value) {
                  _showIndividualCommercialSeats = value;
                  setState(() {});
                },
        ),
        const Divider(),
        if (showSeats)
          for (final seat in members)
            ListTile(
              key: ValueKey('commercial-seat-${seat.nodeId}'),
              dense: true,
              contentPadding: const EdgeInsets.symmetric(horizontal: 8),
              leading: Icon(
                  controller.isProtected(seat.nodeId)
                      ? Icons.lock_clock
                      : Icons.event_seat,
                  size: 20),
              title: Text(seat.title),
              subtitle: Text(_productText(seat.productId),
                  overflow: TextOverflow.ellipsis),
              trailing: _canEdit
                  ? IconButton(
                      icon: const Icon(Icons.edit_outlined, size: 20),
                      tooltip: BlueprintStrings.editProduct,
                      onPressed: _busy || controller.isProtected(seat.nodeId)
                          ? null
                          : () => _product(seat.nodeId, group: false),
                    )
                  : null,
              onTap:
                  _busy ? null : () => _setCommercialSelection({seat.nodeId}),
            ),
        if (members.isEmpty) Text(BlueprintStrings.emptyGroup),
      ],
    );
  }

  Set<String> get _detailSeatIds => {
        for (final seat in controller.snapshot.seatBindings.values)
          if (_commercialSelection.contains(seat.nodeId) ||
              _commercialSelection.contains(seat.groupNodeId))
            seat.nodeId,
      };

  List<TicketModel> _ticketsForSeats(Set<String> seatIds) {
    final tickets = <int, TicketModel>{};
    for (final id in seatIds) {
      final binding = controller.snapshot.seatBindings[id];
      final spot = controller.adapter.spots[binding?.spotId];
      final source = spot?.blueprint;
      final link = source?.orderProductTickets
          ?.where((item) => item.id == spot?.orderProductTicket)
          .firstOrNull;
      if (link == null) continue;
      final ticket = source?.tickets
          ?.where((item) => item.id == link.ticketId)
          .firstOrNull;
      if (ticket?.id == null ||
          const {OrderModel.stornoState, OrderModel.waitlistedState}
              .contains(ticket!.state)) continue;
      tickets[ticket.id!] = ticket;
    }
    return tickets.values.toList();
  }

  List<int> _temporaryHolds(Set<String> seatIds) => [
        for (final id in seatIds)
          if (controller.snapshot.seatBindings[id] case final binding?)
            if (binding.spotId != null &&
                controller.adapter.spots[binding.spotId]?.orderProductTicket ==
                    null &&
                {BlueprintSeatState.selected, BlueprintSeatState.selectedByMe}
                    .contains(controller.adapter.state(binding)))
              binding.spotId!,
      ];

  Future<void> _releaseTemporaryHolds() async {
    if (!_canOrder || _busy) return;
    final session = controller;
    final seats = Set<String>.from(_detailSeatIds);
    final ids = _temporaryHolds(seats);
    if (ids.isEmpty) return;
    final confirmed = await DialogHelper.showConfirmationDialog(
      context,
      BlueprintStrings.releaseTemporaryReservation,
      BlueprintStrings.releaseTemporaryReservationConfirm,
      confirmButtonMessage: BlueprintStrings.releaseTemporaryReservation,
    );
    if (!mounted ||
        !confirmed ||
        !_canOrder ||
        _busy ||
        !identical(session, controller)) return;
    final current = _temporaryHolds(seats).toSet();
    final selected = ids.where(current.contains).toList();
    if (selected.isEmpty) return;
    setState(() => _operationPending = true);
    try {
      await DbTickets.releaseBlueprintHolds(selected);
      await _refresh();
    } catch (error) {
      if (mounted)
        setState(() => _message = BlueprintStrings.layoutErrorMessage(error));
    } finally {
      if (mounted) setState(() => _operationPending = false);
    }
  }

  Future<void> _cancelSelectedTickets() async {
    if (!_canOrder || _busy) return;
    final session = controller;
    final seatIds = Set<String>.from(_detailSeatIds);
    final tickets = _ticketsForSeats(seatIds);
    if (tickets.isEmpty) return;
    final confirmed = await DataGridActionConfirmation.show<TicketModel>(
      context: context,
      title: BlueprintStrings.cancelReservation,
      message: OrderItemStrings.cancelItemsConfirmationText,
      items: tickets,
      itemsLabel: OrderItemStrings.itemsPlural,
      confirmButtonText: BlueprintStrings.cancelReservation,
      groupBy: (ticket) => ticket.relatedOrder,
    );
    if (!mounted ||
        !confirmed ||
        !_canOrder ||
        _busy ||
        !identical(session, controller)) return;
    final current =
        _ticketsForSeats(seatIds).map((ticket) => ticket.id).toSet();
    final ids =
        tickets.map((ticket) => ticket.id!).where(current.contains).toList();
    if (ids.isEmpty) return;
    setState(() => _operationPending = true);
    try {
      final outcome = await DbTickets.stornoTickets(ids);
      await _refresh();
      if (mounted) await showTicketCancellationUpdates(context, outcome);
    } catch (error) {
      if (mounted)
        setState(() => _message = BlueprintStrings.layoutErrorMessage(error));
    } finally {
      if (mounted) setState(() => _operationPending = false);
    }
  }

  Widget _reservationDetails(Map<String, LayoutNode> tables) {
    final byId = {
      for (final node in controller.layout.document.nodes) node.id: node
    };
    final grouped = <String, List<String>>{};
    for (final id in _commercialSelection) {
      if (byId[id] == null) continue;
      final owner = controller.snapshot.seatBindings[id]?.groupNodeId ?? id;
      grouped.putIfAbsent(owner, () => []).add(id);
    }
    final seats = _detailSeatIds;
    final tickets = _canOrder ? _ticketsForSeats(seats) : <TicketModel>[];
    return Column(
      key: const ValueKey('commercial-detail-panel'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 8, 8),
            child: Row(children: [
              Expanded(
                  child: Text(BlueprintStrings.manageSeats,
                      style: Theme.of(context).textTheme.titleMedium)),
              if (_commercialSelection.isNotEmpty)
                IconButton(
                    tooltip: CommonStrings.close,
                    onPressed: _busy ? null : () => _setCommercialSelection({}),
                    icon: const Icon(Icons.close, size: 20)),
            ])),
        const Divider(height: 1),
        Expanded(
            child: SingleChildScrollView(
          padding: const EdgeInsets.all(16),
          child:
              Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            if (grouped.isEmpty)
              Padding(
                  padding: const EdgeInsets.symmetric(vertical: 24),
                  child: Text(BlueprintStrings.selectTableOrSeat)),
            if (_commercialSelection.length > 1 && _canEdit) ...[
              Text(BlueprintStrings.selectedCount(seats.length)),
              const SizedBox(height: 8),
              FilledButton.tonalIcon(
                  key: const ValueKey('commercial-selection-product'),
                  onPressed: _busy ? null : _bulkProduct,
                  icon: const Icon(Icons.sell_outlined, size: 18),
                  label: Text(BlueprintStrings.assignSelectionProduct)),
              const SizedBox(height: 16),
            ],
            if (grouped.length == 1 &&
                _commercialSelection.length == 1 &&
                !_commercialSelection.contains(grouped.keys.single) &&
                tables.containsKey(grouped.keys.single))
              Align(
                  alignment: Alignment.centerLeft,
                  child: TextButton.icon(
                      key: const ValueKey('commercial-detail-back'),
                      onPressed: _busy
                          ? null
                          : () =>
                              _setCommercialSelection({grouped.keys.single}),
                      icon: const Icon(Icons.arrow_back, size: 18),
                      label: Text(tables[grouped.keys.single]!.label))),
            for (final entry in grouped.entries) ...[
              ...[
                Row(children: [
                  Expanded(
                      child: Text(
                          tables[entry.key]?.label ??
                              byId[entry.key]?.label ??
                              BlueprintStrings.manageSeats,
                          style: Theme.of(context).textTheme.titleSmall)),
                  if (_canEdit &&
                      tables.containsKey(entry.key) &&
                      entry.value.contains(entry.key))
                    IconButton(
                        key: ValueKey('rename-commercial-${entry.key}'),
                        tooltip: CommonStrings.rename,
                        onPressed: _busy
                            ? null
                            : () => _renameCommercial(tables[entry.key]!),
                        icon: const Icon(Icons.edit_outlined, size: 18)),
                ]),
                const SizedBox(height: 12),
              ],
              if (entry.value.contains(entry.key) &&
                  tables.containsKey(entry.key))
                _groupProductDetail(tables[entry.key]!)
              else
                for (final id in entry.value)
                  if (byId[id]!.kind == 'capacityArea')
                    _areaDetail(byId[id]!)
                  else
                    _inspector(context, byId[id]!),
              const SizedBox(height: 16),
              if (grouped.length > 1) const Divider(height: 24),
            ],
            if (_canOrder && _temporaryHolds(seats).isNotEmpty) ...[
              const Divider(height: 24),
              OutlinedButton.icon(
                key: const ValueKey('commercial-release-holds'),
                onPressed: _busy ? null : _releaseTemporaryHolds,
                icon: const Icon(Icons.lock_open_outlined, size: 18),
                label: Text(BlueprintStrings.releaseTemporaryReservation),
              ),
            ],
            if (tickets.isNotEmpty) ...[
              const Divider(height: 24),
              OutlinedButton.icon(
                  key: const ValueKey('commercial-cancel-tickets'),
                  style: OutlinedButton.styleFrom(
                      foregroundColor: Theme.of(context).colorScheme.error),
                  onPressed: _busy ? null : _cancelSelectedTickets,
                  icon: const Icon(Icons.event_busy_outlined, size: 18),
                  label: Text(BlueprintStrings.cancelReservation)),
            ],
          ]),
        )),
      ],
    );
  }

  Widget _reservationsPanel(Map<String, LayoutNode> tables) {
    final areas = controller.layout.document.nodes
        .where((node) => node.kind == 'capacityArea')
        .toList();
    final selectedGroups = {
      ..._selectedCommercialGroups,
      for (final id in _commercialSelection)
        if (controller.snapshot.seatBindings[id]?.groupNodeId != null)
          controller.snapshot.seatBindings[id]!.groupNodeId!,
    };
    return Column(
      key: const ValueKey('blueprint-reservations-panel'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Expanded(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (areas.isNotEmpty) ...[
                  Text(BlueprintStrings.standingAreas,
                      style: Theme.of(context).textTheme.titleMedium),
                  for (final area in areas)
                    MouseRegion(
                      onEnter: (_) =>
                          controller.layout.highlightObjects({area.id}),
                      onExit: (_) => controller.layout.highlightObjects({}),
                      child: ListTile(
                        key: ValueKey('commercial-area-${area.id}'),
                        contentPadding: EdgeInsets.zero,
                        selected: _commercialSelection.contains(area.id),
                        title: Text(area.label.isEmpty
                            ? BlueprintStrings.standingAreas
                            : area.label),
                        subtitle: Text(_productText(controller
                            .snapshot.areaBindings[area.id]?.productId)),
                        onTap:
                            _busy ? null : () => _selectCommercialRow(area.id),
                      ),
                    ),
                  const Divider(),
                ],
                Row(children: [
                  Expanded(
                      child: Text(BlueprintStrings.tablesTitle,
                          style: Theme.of(context).textTheme.titleMedium)),
                  if (_canEdit) ...[
                    IconButton(
                        key: const ValueKey('commercial-undo'),
                        tooltip: VenueLayoutStrings.text(context, 'Undo'),
                        onPressed: _busy || !controller.layout.canUndo
                            ? null
                            : controller.layout.undo,
                        icon: const Icon(Icons.undo, size: 18)),
                    IconButton(
                        key: const ValueKey('commercial-redo'),
                        tooltip: VenueLayoutStrings.text(context, 'Redo'),
                        onPressed: _busy || !controller.layout.canRedo
                            ? null
                            : controller.layout.redo,
                        icon: const Icon(Icons.redo, size: 18)),
                  ],
                ]),
                Text(BlueprintStrings.tableSelectionHint,
                    style: Theme.of(context).textTheme.bodySmall),
                if (tables.isEmpty) Text(BlueprintStrings.noTables),
                for (final table in tables.values)
                  _commercialTableRow(table, selectedGroups.contains(table.id)),
              ],
            ),
          ),
        ),
      ],
    );
  }

  String _tableTooltip(LayoutNode table) {
    final id = _commercialId(table);
    final members = controller.snapshot.seatBindings.values
        .where((seat) => seat.groupNodeId == id)
        .toList();
    final products = members.map((seat) => seat.productId).toSet();
    return [
      controller.layout.document.nodes
          .firstWhere((node) => node.id == id)
          .label,
      BlueprintStrings.seatCount(members.length),
      products.length > 1
          ? BlueprintStrings.mixedProducts
          : _productText(products.isEmpty
              ? controller.snapshot.groupProducts[id]
              : products.single),
    ].join('\n');
  }

  Map<String, dynamic> get _presentations => {
        if (!_editingPlan)
          for (final node in controller.layout.document.nodes)
            if (node.kind == 'table') node.id: {'tooltip': _tableTooltip(node)},
        for (final binding in controller.snapshot.seatBindings.values)
          binding.nodeId: {
            'label': binding.title,
            for (final entry
                in controller.adapter.publicPresentation(binding).entries)
              if (!_editingPlan || entry.key != 'fill') entry.key: entry.value,
            'selected': controller.operationSelection.contains(binding.nodeId),
            'highlighted': _legendHover != null &&
                (_legendHover == BlueprintSeatState.selectedByMe
                    ? controller.operationSelection.contains(binding.nodeId)
                    : controller.adapter.state(binding) == _legendHover),
            'tooltip': !_editingPlan &&
                    _canOrder &&
                    controller.adapter.spots[binding.spotId] != null
                ? controller.adapter.spots[binding.spotId]!
                    .blueprintTooltip(context)
                : [
                    binding.title,
                    BlueprintStrings.seatState(
                        controller.adapter.state(binding).name),
                    _productText(binding.productId),
                  ].join('\n'),
            'accessibilityLabel':
                '${binding.title}, ${_productText(binding.productId)}, ${BlueprintStrings.seatState(controller.adapter.state(binding).name)}',
          },
      };

  Widget _modeSelector() => ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 460),
        child: LayoutBuilder(
          builder: (context, constraints) =>
              SegmentedButton<_BlueprintScreenMode>(
            direction:
                constraints.maxWidth < 400 ? Axis.vertical : Axis.horizontal,
            key: const ValueKey('blueprint-screen-mode'),
            showSelectedIcon: true,
            style: ButtonStyle(
              minimumSize: const WidgetStatePropertyAll(Size(0, 44)),
              textStyle: const WidgetStatePropertyAll(
                  TextStyle(fontWeight: FontWeight.w700)),
              backgroundColor: WidgetStateProperty.resolveWith((states) =>
                  states.contains(WidgetState.selected)
                      ? Theme.of(context).colorScheme.primaryContainer
                      : Theme.of(context).colorScheme.surface),
              foregroundColor: WidgetStateProperty.resolveWith((states) =>
                  states.contains(WidgetState.disabled)
                      ? Theme.of(context)
                          .colorScheme
                          .onSurface
                          .withValues(alpha: .38)
                      : states.contains(WidgetState.selected)
                          ? Theme.of(context).colorScheme.onPrimaryContainer
                          : Theme.of(context).colorScheme.onSurfaceVariant),
              side: WidgetStatePropertyAll(BorderSide(
                  color: Theme.of(context).colorScheme.outlineVariant)),
            ),
            segments: [
              ButtonSegment(
                  value: _BlueprintScreenMode.reservations,
                  icon: const Icon(Icons.event_seat_outlined),
                  label: Text(BlueprintStrings.reservationsAndOrders,
                      key: const ValueKey('blueprint-reservations-mode'))),
              if (_canEdit)
                ButtonSegment(
                    value: _BlueprintScreenMode.edit,
                    icon: const Icon(Icons.edit_outlined),
                    label: Text(BlueprintStrings.editPlan,
                        key: const ValueKey('blueprint-edit-mode'))),
            ],
            selected: {_screenMode},
            onSelectionChanged:
                _busy ? null : (modes) => _setScreenMode(modes.single),
          ),
        ),
      );

  Set<String> get _blockableSeatIds {
    final ids =
        _detailSeatIds.where((id) => !controller.isProtected(id)).toSet();
    for (final unit in controller.layout.document.selectionUnits) {
      final members = Set<String>.from(unit['nodeIds'] as List? ?? const []);
      if (!members.any(ids.contains)) continue;
      if (members.any(controller.isProtected)) {
        ids.removeAll(members);
      } else {
        ids.addAll(members);
      }
    }
    return ids;
  }

  void _toggleSelectedBlocked() {
    final ids = _blockableSeatIds;
    if (_busy || !_canEdit || ids.isEmpty) return;
    final block =
        ids.any((id) => !controller.snapshot.seatBindings[id]!.blocked);
    _run(() async => controller.setBlockedForSeats(ids, block));
  }

  Widget _reservationAction(
          {required Key key,
          required String label,
          required IconData icon,
          VoidCallback? onPressed}) =>
      OutlinedButton.icon(
          key: key,
          onPressed: onPressed,
          icon: Icon(icon, size: 18),
          label: Text(label));

  Widget _blockAction() {
    final ids = _blockableSeatIds;
    final unblock = ids.isNotEmpty &&
        ids.every((id) => controller.snapshot.seatBindings[id]!.blocked);
    return _reservationAction(
      key: const ValueKey('blueprint-toggle-blocked'),
      onPressed: _busy || ids.isEmpty ? null : _toggleSelectedBlocked,
      icon: unblock ? Icons.lock_open_outlined : Icons.block_outlined,
      label:
          unblock ? BlueprintStrings.unblockSeats : BlueprintStrings.blockSeats,
    );
  }

  Widget _toolbarActions() => Wrap(
        key: const ValueKey('blueprint-toolbar-actions'),
        crossAxisAlignment: WrapCrossAlignment.center,
        spacing: 8,
        runSpacing: 8,
        children: [
          if (!_editingPlan &&
              _canOrder &&
              controller.mode == BlueprintLayoutMode.manage) ...[
            Tooltip(
              message: BlueprintStrings.legendCreateOrder,
              child: _reservationAction(
                key: const ValueKey('blueprint-start-order'),
                onPressed: _busy
                    ? null
                    : () => _startOperation(BlueprintLayoutMode.order),
                icon: Icons.add_shopping_cart,
                label: BlueprintStrings.orderAction,
              ),
            ),
            _reservationAction(
              key: const ValueKey('blueprint-start-swap'),
              onPressed: _busy
                  ? null
                  : () => _startOperation(BlueprintLayoutMode.swap),
              icon: Icons.swap_horiz,
              label: BlueprintStrings.legendSwapSeats,
            ),
          ],
          if (!_editingPlan &&
              _canEdit &&
              controller.mode == BlueprintLayoutMode.manage)
            _blockAction(),
        ],
      );

  Widget? _operationPanel() {
    if (_editingPlan || controller.mode == BlueprintLayoutMode.manage)
      return null;
    final ordering = controller.mode == BlueprintLayoutMode.order;
    final totals = <String?, double>{};
    for (final id in controller.operationSelection) {
      final binding = controller.snapshot.seatBindings[id];
      final product =
          binding == null ? null : controller.adapter.product(binding);
      if (product?.price != null) {
        totals.update(product!.currencyCode, (v) => v + product.price!,
            ifAbsent: () => product.price!);
      }
    }
    final total = totals.isEmpty
        ? Utilities.formatPrice(context, 0)
        : totals.entries
            .map((e) =>
                Utilities.formatPrice(context, e.value, currencyCode: e.key))
            .join(' + ');
    final valid = !_busy &&
        controller.selectedSpotIds.isNotEmpty &&
        (ordering || controller.selectedSpotIds.length == 2);
    return ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 720),
        child: Material(
          key: const ValueKey('blueprint-operation-panel'),
          elevation: 8,
          color: Theme.of(context).colorScheme.surfaceContainerHigh,
          shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(8),
              side: BorderSide(
                  color: Theme.of(context).colorScheme.outlineVariant)),
          child: Padding(
              padding: const EdgeInsets.all(12),
              child: Wrap(
                alignment: WrapAlignment.center,
                crossAxisAlignment: WrapCrossAlignment.center,
                spacing: 16,
                runSpacing: 8,
                children: [
                  Icon(
                      ordering
                          ? Icons.shopping_cart_outlined
                          : Icons.swap_horiz,
                      color: Theme.of(context).colorScheme.primary),
                  Semantics(
                      liveRegion: true,
                      child: Column(
                          mainAxisSize: MainAxisSize.min,
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                                ordering
                                    ? BlueprintStrings.orderSelectionTitle
                                    : BlueprintStrings.legendSwapSeats,
                                style: const TextStyle(
                                    fontWeight: FontWeight.bold)),
                            Text(ordering
                                ? '${BlueprintStrings.selectedCount(controller.operationSelection.length)} · $total'
                                : '${controller.operationSelection.length} / 2'),
                          ])),
                  TextButton(
                      key: const ValueKey('blueprint-cancel-operation'),
                      onPressed: _busy ? null : _cancelOperation,
                      child: Text(CommonStrings.storno)),
                  FilledButton(
                      onPressed: valid ? (ordering ? _order : _swap) : null,
                      child: Text(ordering
                          ? BlueprintStrings.confirmOrder
                          : BlueprintStrings.legendSwapSeats)),
                ],
              )),
        ));
  }

  Widget _seatHelp() => IconButton(
        key: const ValueKey('blueprint-help'),
        constraints: const BoxConstraints.tightFor(width: 24, height: 24),
        padding: EdgeInsets.zero,
        tooltip: BlueprintStrings.helpTitle,
        icon: const Icon(Icons.info_outline),
        onPressed: () => showDialog<void>(
          context: context,
          builder: (context) => AppAlertDialog(
            title: Text(BlueprintStrings.helpTitle),
            content: BlueprintLayoutHelp(
              editing: _editingPlan,
              canEnterEdit: !_editingPlan &&
                  _canEdit &&
                  controller.mode == BlueprintLayoutMode.manage,
              legend: BlueprintLayoutLegend(
                  states: controller.snapshot.seatBindings.values
                      .map(controller.adapter.state)),
            ),
            actions: [
              TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: Text(CommonStrings.close))
            ],
          ),
        ),
      );

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
      animation: controller,
      builder: (context, _) {
        final tables = _commercialTables;
        return CallbackShortcuts(
            bindings: {
              const SingleActivator(LogicalKeyboardKey.escape): () {
                if (!_editingPlan) _cancelOperation();
              }
            },
            child: Focus(
                focusNode: _hostFocus,
                autofocus: true,
                onKeyEvent: _hostHistoryKey,
                child: Scaffold(
                  body: SafeArea(
                      child: BlueprintEditorFeedback(
                      message: _message,
                      onDismiss: () => setState(() => _message = null),
                      child: Column(children: [
                    if (_saveFlight != null) const LinearProgressIndicator(),
                    if (_assetsFailed)
                      TextButton(
                          onPressed: _assetsPending ? null : _loadAssets,
                          child: Text(CommonStrings.retry)),
                    Expanded(
                        child: AbsorbPointer(
                            absorbing: _busy || _assetsFailed,
                            child: BlueprintPlanEditor(
                                controller: controller.layout,
                                footerTrailing: _seatHelp(),
                                canvasBottomOverlay: _operationPanel(),
                                canvasHeader: _editingPlan
                                    ? null
                                    : BlueprintLayoutLegend(
                                        compact: true,
                                        onHover: (state) => setState(
                                            () => _legendHover = state),
                                        states: controller
                                            .snapshot.seatBindings.values
                                            .map(controller.adapter.state),
                                      ),
                                toolbarPrefix: _modeSelector(),
                                toolbarLeading: _toolbarActions(),
                                onRenameNode: _renameFromInspector,
                                loadTextResources: () => _fonts,
                                occasionId: controller.snapshot.occasionId,
                                busy: _busy,
                                onBusyChanged: (busy) {
                                  if (mounted)
                                    setState(() => _operationPending = busy);
                                },
                                toolbarTrailing: _canEdit
                                    ? EditorActionBar(
                                        inline: true,
                                        hasChanges: controller.isDirty,
                                        enabled: !_busy,
                                        onSave: () => _run(_save),
                                        onDiscard: () => _run(
                                            () async => controller.cancel()),
                                      )
                                    : null,
                                libraryOverride: _editingPlan
                                    ? null
                                    : _reservationsPanel(tables),
                                inspectorOverride: _editingPlan
                                    ? null
                                    : _reservationDetails(tables),
                                viewSelection: _editingPlan
                                    ? null
                                    : controller.mode ==
                                            BlueprintLayoutMode.manage
                                        ? _commercialSelection
                                        : controller.operationSelection,
                                onViewSelectionChanged: _editingPlan
                                    ? null
                                    : _selectCommercialFromCanvas,
                                viewSelectionTarget: _viewSelectionTarget,
                                viewSelectableIds: _editingPlan
                                    ? null
                                    : {
                                        for (final node
                                            in controller.layout.document.nodes)
                                          if (node.kind == 'seat' ||
                                              node.kind == 'capacityArea' ||
                                              (controller.mode ==
                                                      BlueprintLayoutMode
                                                          .manage &&
                                                  (node.kind == 'table' ||
                                                      tables.containsKey(
                                                          node.id))))
                                            node.id,
                                      },
                                readOnlyLabelNodeIds: {
                                  for (final node
                                      in controller.layout.document.nodes)
                                    if (const {'seat', 'table', 'capacityArea'}
                                            .contains(node.kind) ||
                                        tables.containsKey(node.id))
                                      node.id,
                                },
                                seatPresentation: _presentations,
                                interactionEnabled: _editingPlan,
                                showGallery: _editingPlan && _canEdit,
                                onEditRequested: !_editingPlan &&
                                        _canEdit &&
                                        controller.mode ==
                                            BlueprintLayoutMode.manage
                                    ? _editFromCanvas
                                    : null,
                                onNodeActivated: controller.activateNode))),
                  ]))),
                )));
      });
}
