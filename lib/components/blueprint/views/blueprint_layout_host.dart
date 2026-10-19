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
import 'package:venue_seat_picker/venue_seat_picker.dart';
import '../blueprint_layout_contract.dart';
import '../blueprint_group_binding.dart';
import '../blueprint_layout_resources.dart';
import '../../fonts/font_family_picker.dart';
import '../../fonts/ticket_font_ids.dart';
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
    controller.dispose();
    super.dispose();
  }

  void _setScreenMode(_BlueprintScreenMode mode) {
    if (_busy || (mode == _BlueprintScreenMode.edit && !_canEdit)) return;
    controller.layout.cancelGesture();
    controller.layout.select({});
    controller.setMode(BlueprintLayoutMode.manage);
    setState(() => _screenMode = mode);
    _hostFocus.requestFocus();
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
    setState(() {
      _operationPending = true;
      _message = null;
    });
    try {
      await pickBlueprintBackground(
          controller: controller.layout,
          assets: _assets,
          occasionId: controller.snapshot.occasionId,
          isMounted: () => mounted);
    } catch (error) {
      if (mounted) setState(() => _message = error.toString());
    } finally {
      if (mounted) setState(() => _operationPending = false);
    }
  }

  Future<void> _run(Future<void> Function() action) async {
    if (_busy) return;
    setState(() => _message = null);
    try {
      await action();
    } catch (error) {
      if (mounted) setState(() => _message = error.toString());
    }
  }

  Future<void> _save() async {
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
        families: provider.catalog.map((e) => e['family'] as String).toList(),
        extraFamilies: provider.catalog
            .where((e) => e['source'] == 'bundled')
            .map((e) => e['family'] as String)
            .toList(), onSelected: (family) async {
      if (family == null) return;
      final entry = provider.catalog.firstWhere((e) => e['family'] == family);
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
    return '${p.title ?? ""}${price == null ? "" : " · ${Utilities.formatPrice(context, price, currencyCode: p.currencyCode)}"}';
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
                    title: Text(BlueprintStrings.legendBlackArea),
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
  }

  void _selectCommercialRow(String id) {
    final next = HardwareKeyboard.instance.isShiftPressed
        ? {..._commercialSelection}
        : <String>{};
    if (!next.add(id)) next.remove(id);
    _setCommercialSelection(next);
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

  Widget _reservationsPanel(Map<String, LayoutNode> tables) {
    final areas = controller.layout.document.nodes
        .where((node) => node.kind == 'capacityArea')
        .toList();
    final selectedNodes = controller.layout.document.nodes
        .where((node) => _commercialSelection.contains(node.id))
        .toList();
    final selectedGroups = _selectedCommercialGroups;
    final tableRows = tables.values.toList();
    return SingleChildScrollView(
      key: const ValueKey('blueprint-reservations-panel'),
      padding: const EdgeInsets.all(12),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
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
              subtitle: Text(_productText(
                  controller.snapshot.areaBindings[area.id]?.productId)),
              onTap: () => _selectCommercialRow(area.id),
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
        if (tables.isNotEmpty)
          SizedBox(
              height: (tables.length * 64.0).clamp(64, 220).toDouble(),
              child: ListView.builder(
                primary: false,
                itemCount: tableRows.length,
                itemBuilder: (context, index) {
                  final table = tableRows[index];
                  return ListTile(
                    key: ValueKey('commercial-table-${table.id}'),
                    dense: true,
                    contentPadding: EdgeInsets.zero,
                    selected: selectedGroups.contains(table.id),
                    leading: Icon(
                        selectedGroups.contains(table.id)
                            ? Icons.check_circle
                            : Icons.table_restaurant_outlined,
                        size: 20),
                    title: Text(table.label.isEmpty
                        ? BlueprintStrings.tablesTitle
                        : table.label),
                    subtitle: Text(
                        _productText(
                            controller.snapshot.groupProducts[table.id]),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis),
                    onTap: () => _selectCommercialRow(table.id),
                  );
                },
              )),
        const Divider(),
        if (selectedGroups.length > 1) ...[
          Text(BlueprintStrings.selectedCount(selectedGroups.length)),
          if (_canEdit)
            FilledButton.icon(
                key: const ValueKey('commercial-bulk-product'),
                onPressed: _busy ? null : _bulkProduct,
                icon: const Icon(Icons.sell_outlined),
                label: Text(BlueprintStrings.assignProductToGroup)),
        ] else if (selectedNodes.length == 1) ...[
          if (selectedNodes.single.kind == 'capacityArea') ...[
            Text(selectedNodes.single.label,
                style: Theme.of(context).textTheme.titleMedium),
            Text(
                '${selectedNodes.single.properties['capacity'] ?? 0} ${BlueprintStrings.standingAreas}'),
            if (_canEdit &&
                controller.products.containsKey(controller
                    .snapshot.areaBindings[selectedNodes.single.id]?.productId))
              TextButton.icon(
                  key: const ValueKey('commercial-area-product'),
                  onPressed: _busy
                      ? null
                      : () => _editAreaProduct(selectedNodes.single),
                  icon: const Icon(Icons.sell_outlined),
                  label: Text(BlueprintStrings.editAreaProduct)),
            if (_canEdit)
              Text(BlueprintStrings.catalogSaveNotice,
                  style: Theme.of(context).textTheme.bodySmall),
            if (_canEdit)
              TextButton.icon(
                  onPressed: _busy
                      ? null
                      : () => _renameCommercial(selectedNodes.single),
                  icon: const Icon(Icons.edit_outlined),
                  label: Text(CommonStrings.rename)),
          ] else
            _inspector(context, selectedNodes.single),
        ] else
          Text(BlueprintStrings.selectTableOrSeat),
      ]),
    );
  }

  Map<String, dynamic> get _presentations => {
        for (final binding in controller.snapshot.seatBindings.values)
          binding.nodeId: {
            'label': binding.title,
            ...controller.adapter.publicPresentation(binding),
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
                child: Text(CommonStrings.cancel)),
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
                                    : _setCommercialSelection,
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
