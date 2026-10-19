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
    _fonts = BlueprintLayoutFontProvider.load(controller.snapshot.occasionId);
    _loadAssets();
  }

  @override
  void dispose() {
    _fontGeneration++;
    _assets.dispose();
    controller.dispose();
    super.dispose();
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
      if (done == true) await _refresh();
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
    final ids = controller.layout.selection
        .where(controller.snapshot.seatBindings.containsKey)
        .toSet();
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
      await _run(() async =>
          controller.assignProducts(ids, product.id!, freeOnly: freeOnly));
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
                          onTap: !_canEdit ||
                                  _busy ||
                                  controller.isProtected(seat.nodeId)
                              ? null
                              : () => _product(seat.nodeId))
                  ]),
          ],
        ));
  }

  Widget _groupChooser() {
    final groupIds = {
      ...controller.snapshot.groupProducts.keys,
      ...controller.snapshot.seatBindings.values
          .map((seat) => seat.groupNodeId)
          .whereType<String>(),
    };
    final groups = controller.layout.document.nodes
        .where((node) => node.kind == 'group' || groupIds.contains(node.id))
        .toList()
      ..sort((a, b) => Utilities.naturalCompare(a.label, b.label));
    if (groups.isEmpty) return const SizedBox.shrink();
    final selected = controller.layout.selection;
    final value =
        selected.length == 1 && groups.any((g) => g.id == selected.first)
            ? selected.first
            : null;
    return ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 240),
      child: DropdownButton<String>(
        isExpanded: true,
        value: value,
        hint: Text(BlueprintStrings.groupsTitle),
        items: groups
            .map((group) => DropdownMenuItem(
                  value: group.id,
                  child: Text(
                      group.label.isEmpty
                          ? BlueprintStrings.groupsTitle
                          : group.label,
                      overflow: TextOverflow.ellipsis),
                ))
            .toList(),
        onChanged: _busy
            ? null
            : (id) {
                if (id != null) controller.layout.select({id});
              },
      ),
    );
  }

  Map<String, dynamic> get _presentations => {
        for (final binding in controller.snapshot.seatBindings.values)
          binding.nodeId: {
            'label': binding.title,
            ...controller.adapter.publicPresentation(binding),
            'selected': controller.operationSelection.contains(binding.nodeId),
            'tooltip': '${binding.title}\n${_productText(binding.productId)}',
            'accessibilityLabel':
                '${binding.title}, ${_productText(binding.productId)}, ${BlueprintStrings.seatState(controller.adapter.state(binding).name)}',
          },
      };

  Widget _toolbarActions() => Row(
        key: const ValueKey('blueprint-toolbar-actions'),
        mainAxisSize: MainAxisSize.min,
        children: [
          DropdownButtonHideUnderline(
            child: DropdownButton<BlueprintLayoutMode>(
              value: controller.mode,
              onChanged: _busy
                  ? null
                  : (mode) {
                      if (mode != null) controller.setMode(mode);
                    },
              items: [
                for (final mode in BlueprintLayoutMode.values)
                  if (mode == BlueprintLayoutMode.manage || _canOrder)
                    DropdownMenuItem(
                        value: mode,
                        child: Text(switch (mode) {
                          BlueprintLayoutMode.manage =>
                            BlueprintStrings.manageSeats,
                          BlueprintLayoutMode.order =>
                            BlueprintStrings.legendCreateOrder,
                          BlueprintLayoutMode.swap =>
                            BlueprintStrings.legendSwapSeats,
                        })),
              ],
            ),
          ),
          if (controller.mode == BlueprintLayoutMode.manage) _groupChooser(),
          if (_canEdit)
            IconButton(
                onPressed: _busy ? null : _chooseFont,
                tooltip: BlueprintStrings.fontFamily,
                icon: const Icon(Icons.font_download_outlined)),
          if (_canEdit &&
              controller.mode == BlueprintLayoutMode.manage &&
              controller.layout.selection.length > 1)
            TextButton.icon(
                onPressed: _busy ? null : _bulkProduct,
                icon: const Icon(Icons.sell_outlined),
                label: Text(BlueprintStrings.selectedCount(
                    controller.layout.selection.length))),
          if (_canEdit && controller.mode == BlueprintLayoutMode.manage)
            IconButton(
                tooltip: BlueprintStrings.background,
                icon: const Icon(Icons.image_outlined),
                onPressed: _busy ? null : _uploadBackground),
          if (_canEdit &&
              controller.mode == BlueprintLayoutMode.manage &&
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
          if (controller.mode != BlueprintLayoutMode.manage) ...[
            Semantics(
                liveRegion: true,
                child: Text(BlueprintStrings.selectedCount(
                    controller.operationSelection.length))),
            TextButton(
                onPressed:
                    _busy ? null : () => controller.setMode(controller.mode),
                child: Text(BlueprintStrings.clearSelection)),
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
      builder: (context, _) => CallbackShortcuts(
              bindings: {
                const SingleActivator(LogicalKeyboardKey.escape): () {
                  if (!_busy) controller.setMode(controller.mode);
                }
              },
              child: Focus(
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
                                  toolbarTrailing: EditorActionBar(
                                    inline: true,
                                    hasChanges: controller.isDirty,
                                    enabled: _canEdit && !_busy,
                                    onSave: () => _run(_save),
                                    onDiscard: () =>
                                        _run(() async => controller.cancel()),
                                  ),
                                  inspectorBuilder: _inspector,
                                  seatPresentation: _presentations,
                                  interactionEnabled: controller.mode ==
                                      BlueprintLayoutMode.manage,
                                  onNodeActivated: controller.activateNode))),
                    ])),
                  ))));
}
