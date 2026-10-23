import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';
import 'dart:ui' as ui;
import 'package:crypto/crypto.dart';
import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';
import 'package:venue_seat_picker/venue_seat_picker.dart';
import 'demo/bundle.dart';
import 'demo/image_header.dart';
import 'demo/storage.dart';
import 'demo/studio_theme.dart';
import 'demo/demo_strings.dart';

void main() => runApp(const ExampleApp());

class ExampleApp extends StatelessWidget {
  const ExampleApp({super.key});
  @override
  Widget build(BuildContext context) => MaterialApp(
    title: 'Venue layout studio',
    debugShowCheckedModeBanner: false,
    theme: studioTheme(),
    locale: const Locale('cs'),
    supportedLocales: VenueLayoutLocalizations.supportedLocales,
    localizationsDelegates: VenueLayoutLocalizations.localizationsDelegates,
    home: const ExamplePage(),
  );
}

class DemoPrices extends LayoutHistoryParticipant {
  Map<String, dynamic> values = {};
  @override
  Object capture() => jsonDecode(jsonEncode(values));
  @override
  Object? prepare(
    VenueLayoutDocument before,
    VenueLayoutDocument after,
    Object? checkpoint, {
    required bool restoring,
    required LayoutEditIntent intent,
  }) {
    final proposed = restoring ? checkpoint : capture();
    if (proposed is! Map) {
      throw const FormatException('Invalid price checkpoint');
    }
    final ids = {
      for (final n in after.nodes)
        if (const {
          'seat',
          'table',
          'group',
          'furniture',
          'capacityArea',
        }.contains(n.kind))
          n.id,
    };
    final next = <String, dynamic>{};
    for (final entry in proposed.entries) {
      if (entry.key is! String ||
          entry.value is! int ||
          entry.value < 0 ||
          entry.value > 100000000) {
        throw const FormatException('Invalid sample price');
      }
      if (ids.contains(entry.key)) {
        next[entry.key as String] = entry.value;
      } else if (restoring) {
        throw const FormatException('Orphaned price checkpoint');
      }
    }
    return frozenMap(next);
  }

  @override
  void restore(Object? checkpoint) {
    values = Map<String, dynamic>.from(checkpoint as Map);
  }

  int price(LayoutNode node, VenueLayoutDocument doc) {
    if (values[node.id] is int) return values[node.id] as int;
    if (node.parentId != null && values[node.parentId] is int) {
      return values[node.parentId] as int;
    }
    return 250;
  }
}

class ExamplePage extends StatefulWidget {
  const ExamplePage({super.key});
  @override
  State<ExamplePage> createState() => _ExamplePageState();
}

class _ExamplePageState extends State<ExamplePage> {
  late VenueLayoutController controller;
  final prices = DemoPrices();
  Timer? debounce;
  VenueLayoutDocument? _observedDocument;
  Map<String, dynamic>? _observedResources, _observedPrices;
  String? _observedError;
  bool _observedSaving = false, _observedGesture = false;
  Map<String, dynamic> resources = {};
  VenueLayoutDocument? baseline;
  Map<String, dynamic> baselinePrices = {};
  String template = VenueLayoutTemplates.defaultId;
  String status = 'Loading local resources';
  String scenario = 'success';
  bool _savePreparing = false;
  bool loading = true,
      preview = false,
      diagnostic = false,
      storageFailure = false;
  Set<String> selected = {};
  Map<String, int> quantities = {};
  int revision = 0;
  int fontRequest = 0;
  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      resources = await loadLayoutFixtureResources();
      var doc = VenueLayoutTemplates.create(template, localize: demoText);
      VenueLayoutDocument? recoveredBaseline;
      Map<String, dynamic>? recoveredPrices;
      try {
        final saved = await readPreviewDraft() ?? readDraft();
        if (saved != null) {
          final bundle = DemoBundle.decode(
            Uint8List.fromList(utf8.encode(saved)),
          );
          doc = bundle.document;
          if (bundle.host['savedBaseline'] is Map) {
            recoveredBaseline = VenueLayoutDocument.fromJson(
              Map<String, dynamic>.from(bundle.host['savedBaseline']),
            );
            if (validateDocument(recoveredBaseline).isNotEmpty) {
              throw const FormatException('Invalid saved baseline');
            }
            recoveredPrices = Map<String, dynamic>.from(
              bundle.host['savedPrices'] as Map? ?? {},
            );
          }
          resources = bundle.resources;
          prices.values = Map<String, dynamic>.from(
            bundle.host['prices'] as Map? ?? {},
          );
          template = bundle.host['template'] as String? ?? template;
          status = 'Recovered local draft';
        } else {
          status = 'Demo - sample data';
        }
      } catch (_) {
        status =
            'Local storage unavailable or draft invalid. File export remains available.';
      }
      resources = await _decodeImages(resources);
      doc = localizeLayoutDefaultLabels(doc, demoText);
      _attach(doc);
      baseline = recoveredBaseline == null
          ? doc
          : localizeLayoutDefaultLabels(recoveredBaseline, demoText);
      baselinePrices = recoveredPrices ?? Map.from(prices.values);
      controller.setSavedBaseline(
        baseline!,
        participantCheckpoints: [baselinePrices],
      );
    } catch (e) {
      status = 'Local resources unavailable: $e';
      _attach(VenueLayoutTemplates.create(template, localize: demoText));
    }
    if (mounted) setState(() => loading = false);
  }

  Future<ui.Image> _decodeImage(
    Uint8List bytes, {
    int? width,
    int? height,
  }) async {
    final intrinsic = readRasterDimensions(bytes);
    if (bytes.length > DemoBundle.maxAssetBytes ||
        intrinsic.width > 40000000 ||
        intrinsic.height > 40000000 ||
        intrinsic.width * intrinsic.height > 40000000) {
      throw const FormatException('Image exceeds local demo limits');
    }
    ui.Codec? codec;
    ui.Image? image;
    try {
      codec = await ui.instantiateImageCodec(bytes);
      image = (await codec.getNextFrame()).image;
      // JPEG orientation can swap dimensions. Pixel count is preflighted from
      // the encoded header; persisted metadata must match the decoded image.
      final sameDimensions =
          image.width == intrinsic.width && image.height == intrinsic.height ||
          image.width == intrinsic.height && image.height == intrinsic.width;
      if (!sameDimensions ||
          image.width * image.height > 40000000 ||
          width != null && image.width != width ||
          height != null && image.height != height) {
        throw const FormatException('Embedded image dimensions differ');
      }
      return image;
    } catch (_) {
      image?.dispose();
      rethrow;
    } finally {
      codec?.dispose();
    }
  }

  Future<Map<String, dynamic>> _decodeImages(
    Map<String, dynamic> source,
  ) async {
    final images = <String, ui.Image>{};
    final created = <ui.Image>[];
    try {
      for (final entry in (source['assets'] as Map? ?? {}).entries) {
        final existing = (source['images'] as Map?)?[entry.key];
        if (existing is ui.Image) {
          images[entry.key as String] = existing;
          continue;
        }
        final asset = entry.value as Map;
        final image = await _decodeImage(
          Uri.parse(asset['url'] as String).data!.contentAsBytes(),
          width: asset['width'] as int?,
          height: asset['height'] as int?,
        );
        images[entry.key as String] = image;
        created.add(image);
      }
      return {...source, 'images': images};
    } catch (_) {
      for (final image in created) {
        image.dispose();
      }
      rethrow;
    }
  }

  Future<void> _background() async {
    ui.Image? allocated;
    try {
      final file = await openFile(
        acceptedTypeGroups: [
          const XTypeGroup(
            label: 'Raster image',
            extensions: ['png', 'jpg', 'jpeg', 'webp'],
          ),
        ],
      );
      if (file == null) return;
      if (await file.length() > DemoBundle.maxAssetBytes) {
        throw const FormatException('Background exceeds 800 KiB');
      }
      final bytes = await file.readAsBytes();
      final hash = sha256.convert(bytes).toString(), ref = 'image:$hash';
      final existing = (resources['images'] as Map?)?[ref];
      final image = existing is ui.Image ? existing : await _decodeImage(bytes);
      if (existing is! ui.Image) allocated = image;
      if (!mounted) {
        allocated?.dispose();
        return;
      }
      final assets = Map<String, dynamic>.from(
        resources['assets'] as Map? ?? {},
      );
      assets[ref] = {
        'hash': hash,
        'byteLength': bytes.length,
        'url': Uri.dataFromBytes(
          bytes,
          mimeType: file.name.toLowerCase().endsWith('png')
              ? 'image/png'
              : file.name.toLowerCase().endsWith('webp')
              ? 'image/webp'
              : 'image/jpeg',
        ).toString(),
        'mimeType': file.name.toLowerCase().endsWith('png')
            ? 'image/png'
            : file.name.toLowerCase().endsWith('webp')
            ? 'image/webp'
            : 'image/jpeg',
        'width': image.width,
        'height': image.height,
      };
      final candidateResources = <String, dynamic>{
        ...resources,
        'assets': assets,
        'images': {...resources['images'] as Map? ?? {}, ref: image},
      };
      final placement = backgroundPlacement(
        image.width.toDouble(),
        image.height.toDouble(),
        controller.document.canvas,
        fit: 'contain',
      );
      final candidate = controller.document.copyWith(
        background: {...placement, 'assetRef': ref},
      );
      // Keep export available even if a later source would exceed the portable budget.
      DemoBundle(candidate, candidateResources, bundle.host).encode();
      if (!controller.apply(candidate, label: 'Import background')) {
        throw StateError(controller.error ?? 'Background change rejected');
      }
      resources = candidateResources;
      controller.setResources(resources);
      allocated = null;
      setState(() => status = 'Local background embedded in portable export');
    } catch (error) {
      allocated?.dispose();
      if (mounted) setState(() => status = 'Background rejected: $error');
    }
  }

  void _attach(VenueLayoutDocument doc) {
    controller = VenueLayoutController(
      doc,
      resources: resources,
      tableLabelPrefix: demoText('Table'),
    );
    controller.addHistoryParticipant(prices);
    _observedDocument = controller.document;
    _observedResources = controller.resources;
    _observedPrices = prices.values;
    controller.addListener(_controllerChanged);
  }

  DemoBundle get bundle => DemoBundle(controller.document, resources, {
    'prices': prices.values,
    'template': template,
    'revision': revision,
    'label': 'Demo - sample data',
    if (baseline != null) 'savedBaseline': baseline!.toJson(),
    'savedPrices': baselinePrices,
  });
  // Selection belongs to the editor's own listener. It does not invalidate
  // portable data or require rebuilding the demo shell and scheduling writes.
  void _controllerChanged() {
    final dataChanged =
        !identical(_observedDocument, controller.document) ||
        !identical(_observedResources, controller.resources) ||
        !identical(_observedPrices, prices.values);
    final stateChanged =
        _observedError != controller.error ||
        _observedSaving != controller.saving ||
        _observedGesture != controller.gestureActive;
    _observedDocument = controller.document;
    _observedResources = controller.resources;
    _observedPrices = prices.values;
    _observedError = controller.error;
    _observedSaving = controller.saving;
    _observedGesture = controller.gestureActive;
    if (dataChanged || (!controller.gestureActive && stateChanged)) {
      _changed();
    } else if ((stateChanged || diagnostic) && mounted) {
      setState(() {});
    }
  }

  void _changed() {
    if (!mounted) return;
    final nodeIds = controller.document.nodes.map((n) => n.id).toSet();
    prices.values.removeWhere((id, _) => !nodeIds.contains(id));
    selected.removeWhere((id) => !nodeIds.contains(id));
    quantities.removeWhere((id, _) => !nodeIds.contains(id));
    setState(() {});
    debounce?.cancel();
    debounce = Timer(const Duration(milliseconds: 500), () {
      if (controller.gestureActive || controller.saving) return;
      try {
        if (storageFailure) throw StateError('Simulated storage full');
        writeDraft(bundle.encode());
        if (mounted && controller.placementWarningIds.isEmpty) {
          setState(() => status = 'Draft saved on this device');
        }
      } catch (_) {
        if (mounted) {
          setState(
            () => status = 'Storage unavailable. Export your draft to a file.',
          );
        }
      }
    });
  }

  @override
  void dispose() {
    debounce?.cancel();
    if (!loading) controller.dispose();
    for (final image
        in (resources['images'] as Map? ?? {}).values
            .whereType<ui.Image>()
            .toSet()) {
      image.dispose();
    }
    super.dispose();
  }

  Future<bool> _protectDraft() async =>
      !controller.dirty ||
      await showDialog<bool>(
            context: context,
            builder: (context) => AlertDialog(
              title: const Text('Replace unsaved draft?'),
              content: const Text('Save or export first to keep your changes.'),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(context, false),
                  child: const Text('Keep editing'),
                ),
                FilledButton(
                  onPressed: () => Navigator.pop(context, true),
                  child: const Text('Replace'),
                ),
              ],
            ),
          ) ==
          true;
  Future<void> _reset() async {
    if (!await _protectDraft() || !mounted) return;
    controller.beginGesture();
    prices.values = {};
    if (!controller.preview(
      VenueLayoutTemplates.create(template, localize: demoText),
    )) {
      final reason = controller.error;
      controller.cancelGesture();
      setState(() => status = 'Reset rejected: $reason');
      return;
    }
    controller.commitGesture();
    selected = {};
    quantities = {};
    setState(() => status = 'Template restored. Save to confirm baseline.');
  }

  Future<void> _openSampleHall() async {
    if (!await _protectDraft() || !mounted) return;
    controller.beginGesture();
    prices.values = {};
    if (!controller.preview(
      VenueLayoutTemplates.create(VenueLayoutTemplates.defaultId),
    )) {
      controller.cancelGesture();
      return;
    }
    controller.commitGesture();
    setState(() {
      template = VenueLayoutTemplates.defaultId;
      selected = {};
      quantities = {};
      preview = false;
      status = 'Demo - sample data';
    });
  }

  Future<void> _save() async {
    if (_savePreparing || controller.saving || controller.gestureActive) return;
    _savePreparing = true;
    FocusManager.instance.primaryFocus?.unfocus();
    await WidgetsBinding.instance.endOfFrame;
    _savePreparing = false;
    if (!mounted) return;
    final placementIssues = controller.showPlacementWarnings();
    if (placementIssues.isNotEmpty) {
      final overlaps = placementIssues
          .where((issue) => issue.code == 'overlap')
          .length;
      final outside = placementIssues
          .where((issue) => issue.code == 'outside_canvas')
          .length;
      setState(
        () => status =
            'Plánek nelze uložit: překryvy $overlaps, mimo plátno $outside. Uprav červeně označené objekty nebo zvětši plátno.',
      );
      return;
    }
    final issues =
        compileScene(controller.document, resources: resources)['issues']
            as List;
    if (issues.isNotEmpty) {
      setState(
        () => status =
            'Cannot save: ${issues.first['reason']}. Fix the highlighted resource or text issue.',
      );
      return;
    }
    controller.saving = true;
    setState(() {});
    final snapshot = controller.document;
    final priceSnapshot = Map<String, dynamic>.from(prices.values);
    final nextRevision = revision + 1;
    try {
      final portable = DemoBundle(snapshot, resources, {
        'prices': priceSnapshot,
        'template': template,
        'revision': nextRevision,
        'label': 'Demo - sample data',
        'savedBaseline': snapshot.toJson(),
        'savedPrices': priceSnapshot,
      }).encode();
      final result = await _hostResponse();
      if (!mounted) return;
      if (!result.accepted) {
        setState(() => status = result.message!);
        return;
      }
      if (storageFailure) throw StateError('Simulated storage full');
      writeDraft(portable);
      baseline = snapshot;
      baselinePrices = priceSnapshot;
      revision = nextRevision;
      controller.markSaved();
      setState(() => status = 'Saved local baseline, revision $revision');
    } catch (_) {
      if (mounted) {
        setState(
          () =>
              status = 'Save failed. Draft is preserved; export is available.',
        );
      }
    } finally {
      controller.saving = false;
      if (mounted) setState(() {});
    }
  }

  Future<LayoutSelectionResult> _hostResponse() async {
    await Future<void>.delayed(
      Duration(milliseconds: scenario == 'timeout' ? 800 : 100),
    );
    return switch (scenario) {
      'conflict' => LayoutSelectionResult(
        accepted: false,
        message:
            'Demo conflict: another sample revision changed. Draft preserved.',
      ),
      'timeout' => LayoutSelectionResult(
        accepted: false,
        message: 'Demo request timed out. Retry or export your draft.',
      ),
      'resource' => LayoutSelectionResult(
        accepted: false,
        message: 'Demo resource unavailable. Retry with Success.',
      ),
      _ => LayoutSelectionResult(accepted: true),
    };
  }

  Future<void> _export({bool geometry = false}) async {
    try {
      final text = geometry
          ? jsonEncode(controller.document.toJson())
          : bundle.encode();
      final target = await getSaveLocation(
        suggestedName: geometry ? 'venue-layout.json' : 'venue-demo.json',
      );
      if (target == null) return;
      await XFile.fromData(
        Uint8List.fromList(utf8.encode(text)),
        mimeType: 'application/json',
        name: geometry ? 'venue-layout.json' : 'venue-demo.json',
      ).saveTo(target.path);
      if (mounted) {
        setState(
          () => status = geometry
              ? 'Geometry exported without demo prices or states'
              : 'Portable demo exported',
        );
      }
    } catch (e) {
      if (mounted) setState(() => status = 'Export failed: $e');
    }
  }

  Future<void> _webPreview() async {
    try {
      FocusManager.instance.primaryFocus?.unfocus();
      await WidgetsBinding.instance.endOfFrame;
      if (controller.gestureActive || controller.saving) return;
      debounce?.cancel();
      await openWebPreview(bundle.encode());
    } catch (_) {
      if (mounted) {
        setState(
          () => status =
              'Webový náhled se nepodařilo otevřít. Plánek zůstává zachovaný.',
        );
      }
    }
  }

  Future<void> _import() async {
    try {
      final file = await openFile(
        acceptedTypeGroups: [
          const XTypeGroup(label: 'Demo JSON', extensions: ['json']),
        ],
      );
      if (file == null) return;
      if (await file.length() > DemoBundle.maxBytes) {
        throw const FormatException('Import exceeds 16 MiB');
      }
      final imported = DemoBundle.decode(
        await file.readAsBytes(),
      ); // Validate everything before mutation.
      final importedResources = <String, dynamic>{
        ...resources,
        ...imported.resources,
      };
      for (final key in [
        'fontFamilies',
        'fontFaces',
        'textLayouts',
        'numberSymbols',
        'assets',
      ]) {
        final old = resources[key] as Map? ?? {},
            next = imported.resources[key] as Map? ?? {};
        for (final id in next.keys) {
          if (old.containsKey(id) &&
              canonicalContractJson(old[id]) !=
                  canonicalContractJson(next[id])) {
            throw FormatException('Immutable resource collision: $key/$id');
          }
        }
        if (old.isNotEmpty || next.isNotEmpty) {
          importedResources[key] = {...old, ...next};
        }
      }
      DemoBundle(imported.document, importedResources, imported.host).encode();
      if (!await _protectDraft() || !mounted) return;
      final decodedResources = await _decodeImages(importedResources);
      controller.beginGesture();
      prices.values = Map<String, dynamic>.from(
        imported.host['prices'] as Map? ?? {},
      );
      if (!controller.preview(imported.document)) {
        final reason = controller.error;
        controller.cancelGesture();
        throw FormatException('Import blocked: $reason');
      }
      controller.commitGesture();
      resources = decodedResources;
      controller.setResources(resources);
      template = imported.host['template'] as String? ?? template;
      setState(() => status = 'Imported portable draft');
    } catch (e) {
      if (mounted) {
        setState(() => status = 'Import rejected; draft unchanged: $e');
      }
    }
  }

  String _seatLabel(LayoutNode node) {
    final names = <String>[node.label.isEmpty ? 'Seat' : node.label];
    var parent = node.parentId;
    while (parent != null) {
      final matches = controller.document.nodes.where((n) => n.id == parent);
      if (matches.isEmpty) break;
      final n = matches.first;
      if (n.label.isNotEmpty) names.insert(0, n.label);
      parent = n.parentId;
    }
    return names.join(' - ');
  }

  Map<String, dynamic> get presentation => {
    for (final n in controller.document.nodes.where((n) => n.kind == 'seat'))
      n.id: {
        'status': selected.contains(n.id) ? 'selected' : 'available',
        'selected': selected.contains(n.id),
        'price': prices.price(n, controller.document),
        'label': n.label.isEmpty ? 'Seat' : n.label,
        'accessibilityLabel':
            '${_seatLabel(n)} - ${prices.price(n, controller.document)} CZK',
      },
  };
  bool get _statusProblem => RegExp(
    r'failed|unavailable|rejected|cannot|blocked|invalid|timed out|conflict|nelze|nepodařilo',
    caseSensitive: false,
  ).hasMatch(status);

  @override
  Widget build(BuildContext context) {
    if (loading) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }
    final compact = MediaQuery.sizeOf(context).width < 700;
    return Scaffold(
      appBar: AppBar(
        titleSpacing: 20,
        title: Row(
          children: [
            Container(
              width: 34,
              height: 34,
              decoration: BoxDecoration(
                color: const Color(0xffeaf1ff),
                borderRadius: BorderRadius.circular(8),
              ),
              child: const Icon(
                Icons.dashboard_customize_outlined,
                color: Color(0xff2563eb),
                size: 20,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    'EDITOR PLÁNKU',
                    style: Theme.of(context).textTheme.labelSmall?.copyWith(
                      color: const Color(0xff667085),
                      letterSpacing: 1.1,
                      fontSize: 9,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 3),
                  Text(
                    demoText(VenueLayoutTemplates.byId(template).title),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 17,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
        actions: [
          if (!compact)
            Padding(
              padding: const EdgeInsets.only(right: 14),
              child: Text(
                '${controller.document.nodes.where((n) => n.kind == 'seat').length} míst k sezení',
                style: Theme.of(
                  context,
                ).textTheme.bodySmall?.copyWith(color: const Color(0xff667085)),
              ),
            ),
          TextButton.icon(
            onPressed: controller.saving ? null : _webPreview,
            icon: const Icon(Icons.open_in_browser, size: 18),
            label: const Text('Webový náhled'),
          ),
          TextButton.icon(
            onPressed: () => setState(() => preview = !preview),
            icon: Icon(
              preview ? Icons.edit_outlined : Icons.visibility_outlined,
              size: 18,
            ),
            label: Text(preview ? 'Zpět do editoru' : 'Náhled'),
          ),
          const SizedBox(width: 8),
          FilledButton.icon(
            onPressed: controller.saving || _savePreparing ? null : _save,
            icon: Icon(
              controller.saving ? Icons.hourglass_top : Icons.check,
              size: 17,
            ),
            label: Text(controller.saving ? 'Ukládání…' : 'Uložit plánek'),
          ),
          const SizedBox(width: 8),
          PopupMenuButton<String>(
            tooltip: demoText('Files and diagnostics'),
            icon: const Icon(Icons.more_horiz),
            onSelected: (value) {
              if (controller.saving) return;
              switch (value) {
                case 'background':
                  _background();
                case 'export':
                  _export();
                case 'geometry':
                  _export(geometry: true);
                case 'import':
                  _import();
                case 'reset':
                  _reset();
                case 'demo':
                  _openSampleHall();
                case 'diagnostic':
                  setState(() => diagnostic = !diagnostic);
              }
            },
            itemBuilder: (_) => [
              const PopupMenuItem(
                value: 'demo',
                child: Text('Otevřít ukázkový sál (72 míst)'),
              ),
              const PopupMenuDivider(),
              PopupMenuItem(
                value: 'background',
                child: Text(demoText('Import background image')),
              ),
              PopupMenuItem(
                value: 'export',
                child: Text(demoText('Export portable demo')),
              ),
              PopupMenuItem(
                value: 'geometry',
                child: Text(demoText('Export geometry only')),
              ),
              PopupMenuItem(
                value: 'import',
                child: Text(demoText('Import portable demo')),
              ),
              PopupMenuItem(
                value: 'reset',
                child: Text(demoText('Reset template')),
              ),
              PopupMenuItem(
                value: 'diagnostic',
                child: Text(demoText('Diagnostics')),
              ),
            ],
          ),
          const SizedBox(width: 16),
        ],
      ),
      body: Column(
        children: [
          Container(
            height: 32,
            padding: const EdgeInsets.symmetric(horizontal: 20),
            decoration: const BoxDecoration(
              color: Colors.white,
              border: Border(bottom: BorderSide(color: Color(0xffdfe4eb))),
            ),
            child: Row(
              children: [
                Icon(
                  Icons.circle,
                  size: 6,
                  color: _statusProblem
                      ? const Color(0xffb54708)
                      : const Color(0xff12b76a),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Tooltip(
                    message: demoText(status),
                    child: Text(
                      demoText(status),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 11,
                        color: _statusProblem
                            ? const Color(0xffb54708)
                            : const Color(0xff667085),
                      ),
                    ),
                  ),
                ),
                if (!compact)
                  const Text(
                    'UKÁZKOVÁ DATA  ·  bez skutečných rezervací',
                    style: TextStyle(
                      fontSize: 10,
                      color: Color(0xff667085),
                      letterSpacing: .3,
                    ),
                  ),
              ],
            ),
          ),
          if (diagnostic) _diagnostics(),
          Expanded(
            child: preview
                ? Column(
                    children: [
                      Padding(
                        padding: const EdgeInsets.all(8),
                        child: Text(
                          '${selected.length} selected seats - ${quantities.values.fold<int>(0, (a, b) => a + b)} standing selected',
                        ),
                      ),
                      Expanded(
                        child: VenueLayoutPicker(
                          document: controller.document,
                          resources: resources,
                          seatPresentation: presentation,
                          capacityPresentation: {
                            for (final n in controller.document.nodes.where(
                              (n) => n.kind == 'capacityArea',
                            ))
                              n.id: {
                                'capacity': n.properties['capacity'],
                                'selectedQuantity': quantities[n.id] ?? 0,
                                'available': 20,
                              },
                          },
                          onSelectionRequested: (ids, selecting) async {
                            final result = await _hostResponse();
                            if (result.accepted && mounted) {
                              setState(() {
                                if (selecting) {
                                  selected.addAll(ids);
                                } else {
                                  selected.removeAll(ids);
                                }
                              });
                            }
                            return result;
                          },
                          onQuantityRequested: (id, count) async {
                            final result = await _hostResponse();
                            if (result.accepted && mounted) {
                              setState(() => quantities[id] = count);
                            }
                            return result;
                          },
                        ),
                      ),
                    ],
                  )
                : VenueLayoutEditor(
                    seatPresentation: presentation,
                    onImportBackground: _background,
                    controller: controller,
                    onTemplateSelected: (choice) =>
                        setState(() => template = choice.id),
                  ),
          ),
        ],
      ),
    );
  }

  Future<void> _fontRace() async {
    final original = resources;
    final staleRequest = ++fontRequest;
    final slow = Future<void>.delayed(const Duration(milliseconds: 160), () {
      if (staleRequest == fontRequest) {
        controller.setResources({
          'protocol': 2,
          'fontFamilies': {},
          'textLayouts': {},
          'numberSymbols': {},
        });
      }
    });
    final latestRequest = ++fontRequest;
    await Future<void>.delayed(const Duration(milliseconds: 20));
    if (!mounted || latestRequest != fontRequest) return;
    controller.setResources(original);
    await slow;
    if (mounted) {
      setState(
        () => status =
            'Font race simulated: stale result ignored; draft and current resources preserved.',
      );
    }
  }

  Widget _diagnostics() => Padding(
    padding: const EdgeInsets.all(8),
    child: Wrap(
      spacing: 12,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        const Text('Diagnostics: simulated host outcomes'),
        TextButton(
          onPressed: _fontRace,
          child: const Text('Simulate font race'),
        ),
        DropdownButton<String>(
          value: scenario,
          items: [
            for (final s in ['success', 'conflict', 'timeout', 'resource'])
              DropdownMenuItem(value: s, child: Text(s)),
          ],
          onChanged: (v) => setState(() => scenario = v!),
        ),
        FilterChip(
          label: const Text('Storage full'),
          selected: storageFailure,
          onSelected: (v) => setState(() => storageFailure = v),
        ),
        TextButton(
          onPressed: () {
            if (baseline == null) return;
            controller.beginGesture();
            prices.values = Map.from(baselinePrices);
            if (!controller.preview(baseline!)) {
              final reason = controller.error;
              controller.cancelGesture();
              setState(() => status = 'Restore blocked: $reason');
              return;
            }
            controller.commitGesture();
            setState(() => status = 'Restored saved baseline');
          },
          child: const Text('Restore saved baseline'),
        ),
        const Text(
          'Export the same portable demo and import it in the JS picker. No reservations or payments are created.',
        ),
      ],
    ),
  );
}
