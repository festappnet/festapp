import 'dart:async';
import 'dart:convert';
import 'package:http/http.dart' as http;
import 'blueprint_layout_background.dart';
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
import '../../fonts/font_family_picker.dart';
import '../../fonts/ticket_font_ids.dart';
import '../../ticket_layout/ticket_layout_service.dart';
import '../blueprint_layout_controller.dart';
import '../blueprint_model.dart';
import '../blueprint_strings.dart';
import 'blueprint_create_order_dialog.dart';
import 'blueprint_layout_legend.dart';
import 'blueprint_product_dialogs.dart';

enum _BlueprintScreenMode { reservations, edit }

/// Business UI surrounds the public editor; geometry and its history remain in
/// the package, while all prices, rights and commands remain in Festapp.
class BlueprintLayoutHost extends StatefulWidget {
  const BlueprintLayoutHost(
      {super.key, required this.source, required this.reload});
  final BlueprintModel source;
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
  final _commercialDetailRevision = ValueNotifier(0);
  bool _commercialDetailOpen = false;
  bool _showIndividualCommercialSeats = false;
  bool get _editingPlan => _screenMode == _BlueprintScreenMode.edit;
  String? _message;
  final _assets = BlueprintLayoutAssetResolver();
  bool _assetsPending = false;
  bool _assetsFailed = false;
  bool _operationPending = false;
  late final Future<BlueprintLayoutFontProvider> _fonts;
  int _fontGeneration = 0;
  bool get _canEdit => RightsService.canEditOccasion();
  bool get _canOrder => RightsService.canUpdateOrders();
  bool get _busy => controller.isBusy || _operationPending || _assetsPending;

  @override
  void initState() {
    super.initState();
    controller = BlueprintLayoutController(source: widget.source);
    controller.layout.readOnly = !_canEdit;
    // Decide once on entry. Inserting or saving never leaves explicit editing.
    _screenMode = _canEdit && controller.layout.document.nodes.isEmpty
        ? _BlueprintScreenMode.edit
        : _BlueprintScreenMode.reservations;
    _fonts = BlueprintLayoutFontProvider.load(controller.snapshot.occasionId);
    _loadAssets();
  }

  @override
  void dispose() {
    _fontGeneration++;
    _assets.dispose();
    _hostFocus.dispose();
    _commercialDetailRevision.dispose();
    controller.dispose();
    super.dispose();
  }

  void _setScreenMode(_BlueprintScreenMode mode) {
    if (_busy || (mode == _BlueprintScreenMode.edit && !_canEdit)) return;
    if (_editingPlan &&
        mode == _BlueprintScreenMode.reservations &&
        !controller.validatePlacementForReservations()) {
      setState(() => _message = BlueprintStrings.placementInvalid);
      return;
    }
    controller.layout.cancelGesture();
    controller.layout.select({});
    controller.setMode(BlueprintLayoutMode.manage);
    setState(() {
      _screenMode = mode;
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
    controller.setMode(mode);
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
    setState(() {
      _assetsPending = true;
      _assetsFailed = false;
    });
    try {
      final resources = await _assets.resolve(controller.layout.resources);
      if (!mounted) return;
      if (!controller.layout.setResources(resources)) {
        throw StateError('invalid_layout_resources');
      }
    } catch (error) {
      if (mounted)
        setState(() {
          _message = error.toString();
          _assetsFailed = true;
        });
    } finally {
      if (mounted) setState(() => _assetsPending = false);
    }
  }

  Future<void> _uploadBackground() async {
    if (_busy) return;
    var uploading = false;
    try {
      final selection = await showBlueprintBackgroundPicker(context);
      if (selection == null || !mounted || _busy) return;
      uploading = true;
      setState(() {
        _operationPending = true;
        _message = null;
      });
      await uploadBlueprintBackground(
          selection: selection,
          controller: controller.layout,
          assets: _assets,
          occasionId: controller.snapshot.occasionId,
          isMounted: () => mounted);
    } catch (error) {
      if (mounted) {
        setState(() => _message = BlueprintStrings.layoutErrorMessage(error));
      }
    } finally {
      if (mounted && uploading) setState(() => _operationPending = false);
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
      if (mounted) _commercialDetailRevision.value++;
    }
  }

  Future<void> _save() async {
    if (controller.saver.pending == null &&
        !controller.validatePlacementForReservations()) {
      throw StateError('layout_placement_invalid');
    }
    if (controller.saver.pending == null) await _prepareFonts();
    final result = await controller.save();
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

  Future<void> _prepareFonts({String? selectedFont}) async {
    final generation = ++_fontGeneration;
    final provider = await _fonts;
    if (!mounted || generation != _fontGeneration) return;
    final document = controller.layout.document;
    provider.characters = document.nodes
        .map((node) => '${node.label} ${node.properties['text'] ?? ''}')
        .join(' ');
    // Selection-unit counts are also rendered with the document font.
    provider.characters += ' ×0123456789';
    String realId(String id) => switch (id) {
          'fixture:sans' => legacyTicketFontIds['roboto']!,
          'fixture:serif' => legacyTicketFontIds['robotoSlab']!,
          _ => id,
        };
    final defaultId =
        selectedFont ?? realId(document.defaultTextStyle['fontId'] as String);
    final nodes = document.nodes
        .map((node) => node.properties['fontId'] is String
            ? node.copyWith(properties: {
                ...node.properties,
                'fontId': realId(node.properties['fontId'] as String)
              })
            : node)
        .toList();
    final ids = {
      defaultId,
      for (final node in nodes)
        if (node.properties['fontId'] is String)
          node.properties['fontId'] as String
    };
    final fonts = <String, dynamic>{
      ...controller.layout.resources['fonts'] as Map? ?? {}
    };
    for (final id in ids) {
      final current = fonts[id];
      final catalogEntry = provider.catalog.where((font) => font['id'] == id);
      final glyphs = current is Map ? current['glyphs'] : null;
      final reusable = current is Map &&
          current['id'] == id &&
          catalogEntry.isNotEmpty &&
          current['hash'] == catalogEntry.first['sha256'] &&
          glyphs is Map &&
          provider.characters.runes.every((rune) =>
              rune == 10 || glyphs.containsKey(String.fromCharCode(rune))) &&
          validateLayoutResources({
            'protocol': 1,
            'fonts': {id: current}
          }).isEmpty;
      if (reusable) continue;
      fonts[id] = await provider.resolve(id);
    }
    if (!mounted || generation != _fontGeneration) return;
    if (!identical(document, controller.layout.document)) {
      throw StateError(BlueprintStrings.draftChanged);
    }
    final next = document.copyWith(
        nodes: nodes,
        defaultTextStyle: {...document.defaultTextStyle, 'fontId': defaultId});
    if (!controller.layout
        .setResources({...controller.layout.resources, 'fonts': fonts})) {
      throw StateError(controller.layout.error ?? 'invalid_font_resource');
    }
    if (jsonEncode(next.toJson()) != jsonEncode(document.toJson())) {
      controller.layout.apply(next);
    }
  }

  Future<void> _chooseFont() async {
    final provider = await _fonts;
    if (!mounted) return;
    await FontFamilyPicker.showChoices(context,
        families:
            provider.catalog.map((e) => e['family'] as String).toSet().toList(),
        previewStyle: (family) async {
          final entry =
              provider.catalog.firstWhere((e) => e['family'] == family);
          final font = await TicketLayoutService()
              .font(controller.snapshot.occasionId, entry['id'] as String);
          return TextStyle(
              fontFamily: font.loaderName, fontWeight: FontWeight.w400);
        },
        extraFamilies: provider.catalog
            .where((e) => e['source'] == 'bundled')
            .map((e) => e['family'] as String)
            .toList(),
        onSelected: (family) async {
          if (family == null) return;
          final entry =
              provider.catalog.firstWhere((e) => e['family'] == family);
          await _run(() => _prepareFonts(selectedFont: entry['id'] as String));
        });
  }

  Future<void> _refresh() async {
    final source = await widget.reload();
    if (mounted && source != null) controller.refreshLive(source);
  }

  Future<void> _order() async {
    if (!_canOrder || _busy || controller.selectedSpotIds.isEmpty) return;
    setState(() => _operationPending = true);
    try {
      final done = await showDialog<bool>(
          context: context,
          barrierDismissible: false,
          builder: (_) => BlueprintCreateOrderDialog(
              selectedSpotIds: List.of(controller.selectedSpotIds)));
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
      if (confirmed == true && mounted) {
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
        controller.applyGroupProduct(nodeId, picked.id!, freeOnly: freeOnly);
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
            if (commercialGroupId != node.id && commercialGroup != null)
              Text(commercialGroup.label.isEmpty
                  ? commercialGroupId
                  : commercialGroup.label),
            Text(BlueprintStrings.productsTitle,
                style: Theme.of(context).textTheme.titleSmall),
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
            if (binding != null && binding.groupNodeId != null)
              Text(binding.productId == defaultId
                  ? BlueprintStrings.inheritedProduct
                  : BlueprintStrings.productOverride),
            if (protected || blockers > 0)
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
            if (_canEdit) ...[
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
                    subtitle: Text(BlueprintStrings.blockSeatHint),
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
    _commercialDetailRevision.value++;
  }

  void _selectCommercialRow(String id) {
    final next = HardwareKeyboard.instance.isShiftPressed
        ? {..._commercialSelection}
        : <String>{};
    if (!next.add(id)) next.remove(id);
    _setCommercialSelection(next);
    if (!HardwareKeyboard.instance.isShiftPressed) _showCommercialDetail();
  }

  void _selectCommercialFromCanvas(Set<String> selection) {
    if (_editingPlan || _busy || controller.mode != BlueprintLayoutMode.manage)
      return;
    _setCommercialSelection(selection);
    final selectedId =
        _commercialSelection.length == 1 ? _commercialSelection.single : null;
    final openDetail = !HardwareKeyboard.instance.isShiftPressed;
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
      if (openDetail) _showCommercialDetail();
    });
  }

  Future<void> _showCommercialDetail() async {
    if (_busy ||
        _commercialDetailOpen ||
        _commercialSelection.length != 1 ||
        controller.mode != BlueprintLayoutMode.manage) return;
    _commercialDetailOpen = true;
    _showIndividualCommercialSeats = false;
    try {
      await showDialog<void>(
        context: context,
        animationStyle: AnimationStyle.noAnimation,
        builder: (dialogContext) => AnimatedBuilder(
          animation: Listenable.merge([controller, _commercialDetailRevision]),
          builder: (context, _) {
            final node = controller.layout.document.nodes
                .where((node) => _commercialSelection.contains(node.id))
                .firstOrNull;
            final groupId = node == null
                ? null
                : controller.snapshot.seatBindings[node.id]?.groupNodeId;
            return AppAlertDialog(
              key: const ValueKey('commercial-detail-dialog'),
              title: Text(node != null && _commercialTables.containsKey(node.id)
                  ? '${BlueprintStrings.manageGroupProducts}: ${node.label}'
                  : BlueprintStrings.manageSeats),
              content: SizedBox(
                width: 520,
                child: SingleChildScrollView(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      if (_message != null)
                        Semantics(
                          liveRegion: true,
                          child: Text(_message!,
                              style: TextStyle(
                                  color: Theme.of(context).colorScheme.error)),
                        ),
                      if (groupId != null)
                        Align(
                          alignment: Alignment.centerLeft,
                          child: TextButton.icon(
                            key: const ValueKey('commercial-detail-back'),
                            onPressed: _busy
                                ? null
                                : () => _setCommercialSelection({groupId}),
                            icon: const Icon(Icons.arrow_back),
                            label: Text(BlueprintStrings.tablesTitle),
                          ),
                        ),
                      if (node != null)
                        node.kind == 'capacityArea'
                            ? _areaDetail(node)
                            : _commercialTables.containsKey(node.id)
                                ? _groupProductDetail(node)
                                : _inspector(context, node),
                    ],
                  ),
                ),
              ),
            );
          },
        ),
      );
    } finally {
      _commercialDetailOpen = false;
    }
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
    await _run(() async => controller.renameCommercialNode(node.id, value));
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
        final id = await DbEshop.updateProduct(updated);
        if (mounted) controller.upsertCatalogProduct(updated.copyWith(id: id));
      } finally {
        if (mounted) setState(() => _operationPending = false);
      }
    });
  }

  Widget _areaDetail(LayoutNode area) => Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(area.label, style: Theme.of(context).textTheme.titleMedium),
          Text(
              '${area.properties['capacity'] ?? 0} ${BlueprintStrings.standingAreas}'),
          if (_canEdit &&
              controller.products.containsKey(
                  controller.snapshot.areaBindings[area.id]?.productId))
            TextButton.icon(
                key: const ValueKey('commercial-area-product'),
                onPressed: _busy ? null : () => _editAreaProduct(area),
                icon: const Icon(Icons.sell_outlined),
                label: Text(BlueprintStrings.editAreaProduct)),
          if (_canEdit)
            Text(BlueprintStrings.catalogSaveNotice,
                style: Theme.of(context).textTheme.bodySmall),
          if (_canEdit)
            TextButton.icon(
                onPressed: _busy ? null : () => _renameCommercial(area),
                icon: const Icon(Icons.edit_outlined),
                label: Text(CommonStrings.rename)),
        ],
      );

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
          title: Text(
              table.label.isEmpty ? BlueprintStrings.tablesTitle : table.label),
          subtitle: Text(summary, maxLines: 1, overflow: TextOverflow.ellipsis),
          trailing: Text('(${members.length})',
              style: Theme.of(context).textTheme.bodySmall),
          onTap: _busy ? null : () => _selectCommercialRow(table.id),
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
                  _commercialDetailRevision.value++;
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
            )
        else
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 32, horizontal: 16),
            child: Column(children: [
              Icon(Icons.format_list_bulleted,
                  size: 48, color: Theme.of(context).disabledColor),
              const SizedBox(height: 16),
              Text(BlueprintStrings.uniformViewHelp,
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.bodySmall),
            ]),
          ),
        if (members.isEmpty) Text(BlueprintStrings.emptyGroup),
        if (_canEdit)
          Align(
              alignment: Alignment.centerRight,
              child: TextButton.icon(
                key: ValueKey('rename-commercial-${table.id}'),
                onPressed: _busy ? null : () => _renameCommercial(table),
                icon: const Icon(Icons.edit_outlined, size: 18),
                label: Text(CommonStrings.rename),
              )),
      ],
    );
  }

  Widget _reservationsPanel(Map<String, LayoutNode> tables) {
    final areas = controller.layout.document.nodes
        .where((node) => node.kind == 'capacityArea')
        .toList();
    final selectedGroups = _selectedCommercialGroups;
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
                    ListTile(
                      key: ValueKey('commercial-area-${area.id}'),
                      contentPadding: EdgeInsets.zero,
                      selected: _commercialSelection.contains(area.id),
                      title: Text(area.label.isEmpty
                          ? BlueprintStrings.standingAreas
                          : area.label),
                      subtitle: Text(_productText(controller
                          .snapshot.areaBindings[area.id]?.productId)),
                      onTap: _busy ? null : () => _selectCommercialRow(area.id),
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
        if (selectedGroups.length > 1)
          Padding(
            padding: const EdgeInsets.all(12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(BlueprintStrings.selectedCount(selectedGroups.length)),
                if (_canEdit)
                  FilledButton.icon(
                      key: const ValueKey('commercial-bulk-product'),
                      onPressed: _busy ? null : _bulkProduct,
                      icon: const Icon(Icons.sell_outlined),
                      label: Text(BlueprintStrings.assignProductToGroup)),
              ],
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
      table.label,
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

  Widget _toolbarActions() => Row(
        key: const ValueKey('blueprint-toolbar-actions'),
        mainAxisSize: MainAxisSize.min,
        children: [
          // Each mode takes only its label width; equal-width segments would
          // reserve the long reservations label's width twice.
          for (final mode in _BlueprintScreenMode.values)
            if (mode != _BlueprintScreenMode.edit || _canEdit)
              Padding(
                padding: const EdgeInsets.only(right: 4),
                child: ChoiceChip(
                  showCheckmark: false,
                  label: Text(
                      mode == _BlueprintScreenMode.edit
                          ? BlueprintStrings.editPlan
                          : BlueprintStrings.reservationsAndOrders,
                      key: ValueKey(mode == _BlueprintScreenMode.edit
                          ? 'blueprint-edit-mode'
                          : 'blueprint-reservations-mode')),
                  selected: _screenMode == mode,
                  onSelected: _busy ? null : (_) => _setScreenMode(mode),
                ),
              ),
          const SizedBox(width: 12),
          if (_editingPlan && _canEdit)
            IconButton(
                onPressed: _busy ? null : _chooseFont,
                tooltip: BlueprintStrings.fontFamily,
                icon: const Icon(Icons.font_download_outlined)),
          if (_canEdit && _editingPlan)
            IconButton(
                tooltip: BlueprintStrings.background,
                icon: const Icon(Icons.image_outlined),
                onPressed: _busy ? null : _uploadBackground),
          if (_canEdit &&
              _editingPlan &&
              controller.layout.document.background != null)
            IconButton(
                tooltip: BlueprintStrings.removeBackground,
                icon: const Icon(Icons.hide_image_outlined),
                onPressed: _busy
                    ? null
                    : () => controller.layout.apply(
                        controller.layout.document
                            .copyWith(clearBackground: true),
                        label: BlueprintStrings.removeBackground)),
          if (!_editingPlan &&
              _canOrder &&
              controller.mode == BlueprintLayoutMode.manage) ...[
            Tooltip(
              message: BlueprintStrings.legendCreateOrder,
              child: TextButton.icon(
                key: const ValueKey('blueprint-start-order'),
                onPressed: _busy
                    ? null
                    : () => _startOperation(BlueprintLayoutMode.order),
                icon: const Icon(Icons.add_shopping_cart, size: 18),
                label: Text(BlueprintStrings.orderAction),
              ),
            ),
            TextButton.icon(
              key: const ValueKey('blueprint-start-swap'),
              onPressed: _busy
                  ? null
                  : () => _startOperation(BlueprintLayoutMode.swap),
              icon: const Icon(Icons.swap_horiz, size: 18),
              label: Text(BlueprintStrings.legendSwapSeats),
            ),
          ],
          if (!_editingPlan &&
              controller.mode != BlueprintLayoutMode.manage) ...[
            Semantics(
                liveRegion: true,
                child: Text(BlueprintStrings.selectedCount(
                    controller.operationSelection.length))),
            TextButton(
                key: const ValueKey('blueprint-cancel-operation'),
                onPressed: _busy ? null : _cancelOperation,
                child: Text(CommonStrings.storno)),
            FilledButton(
                onPressed: _busy ||
                        controller.selectedSpotIds.isEmpty ||
                        (controller.mode == BlueprintLayoutMode.swap &&
                            controller.selectedSpotIds.length != 2)
                    ? null
                    : controller.mode == BlueprintLayoutMode.order
                        ? _order
                        : _swap,
                child: Text(controller.mode == BlueprintLayoutMode.order
                    ? BlueprintStrings.confirmOrder
                    : BlueprintStrings.legendSwapSeats)),
          ],
          IconButton(
            tooltip: BlueprintStrings.manageSeats,
            icon: const Icon(Icons.info_outline),
            onPressed: () => showDialog<void>(
              context: context,
              builder: (context) => AppAlertDialog(
                content: BlueprintLayoutLegend(
                    states: controller.snapshot.seatBindings.values
                        .map(controller.adapter.state)),
              ),
            ),
          ),
        ],
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
                      child: Column(children: [
                    if (_busy) const LinearProgressIndicator(),
                    if (_message != null)
                      Padding(
                          padding: const EdgeInsets.all(8),
                          child: Semantics(
                              liveRegion: true,
                              child: Text(_message!,
                                  style: TextStyle(
                                      color: Theme.of(context)
                                          .colorScheme
                                          .error)))),
                    if (_assetsFailed)
                      TextButton(
                          onPressed: _assetsPending ? null : _loadAssets,
                          child: Text(CommonStrings.retry)),
                    Expanded(
                        child: AbsorbPointer(
                            absorbing: _busy || _assetsFailed,
                            child: VenueLayoutEditor(
                                controller: controller.layout,
                                toolbarLeading: _toolbarActions(),
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
                                inspectorOverride: _editingPlan
                                    ? null
                                    : _reservationsPanel(tables),
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
                                onNodeActivated: controller.activateNode))),
                  ])),
                )));
      });
}
