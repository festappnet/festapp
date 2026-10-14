import 'package:flutter/material.dart';
import 'package:fstapp/components/_shared/common_strings.dart';
import 'package:fstapp/components/occasion/demo/demo_catalog.dart';
import 'package:fstapp/components/occasion/demo/demo_occasion_strings.dart';
import 'package:fstapp/router_service.dart';

/// Both entry points share metadata loading and the tenant-wide, unfiltered
/// own-work state. Search and the selected Unit never decide onboarding state.
class DemoOccasionsSection extends StatefulWidget {
  final Future<DemoCatalog> Function() load;
  final Future<void> Function(DemoOccasion)? onOpen;
  const DemoOccasionsSection(
      {super.key, this.load = DemoCatalog.load, this.onOpen});
  @override
  State<DemoOccasionsSection> createState() => _DemoOccasionsSectionState();
}

class _DemoOccasionsSectionState extends State<DemoOccasionsSection> {
  DemoCatalog? _catalog;
  bool _expanded = false;
  bool _failed = false;
  int _generation = 0;
  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final generation = ++_generation;
    setState(() => _failed = false);
    try {
      final catalog = await widget.load();
      if (mounted && generation == _generation)
        setState(() => _catalog = catalog);
    } catch (_) {
      if (mounted && generation == _generation) setState(() => _failed = true);
    }
  }

  Future<void> _open(DemoOccasion item) async {
    if (widget.onOpen != null) {
      await widget.onOpen!(item);
    } else {
      await RouterService.navigateToOccasionByLink(context, item.link);
    }
    if (mounted) await _load();
  }

  @override
  Widget build(BuildContext context) {
    if (_failed)
      return Padding(
          padding: const EdgeInsets.all(16),
          child: Row(children: [
            Expanded(child: Text(DemoOccasionStrings.unavailable)),
            TextButton(onPressed: _load, child: Text(CommonStrings.retry))
          ]));
    final catalog = _catalog;
    if (catalog == null)
      return const Padding(
          padding: EdgeInsets.all(16), child: LinearProgressIndicator());
    if (catalog.items.isEmpty) return const SizedBox.shrink();
    final showCards = !catalog.hasOwnWork || _expanded;
    return Padding(
        padding: const EdgeInsets.all(16),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          if (catalog.hasOwnWork)
            TextButton.icon(
                onPressed: () => setState(() => _expanded = !_expanded),
                icon: Icon(_expanded ? Icons.expand_less : Icons.expand_more),
                label: Text(DemoOccasionStrings.inspiration)),
          if (showCards) ...[
            Text(DemoOccasionStrings.heading,
                style: Theme.of(context).textTheme.headlineSmall),
            const SizedBox(height: 8),
            Text(DemoOccasionStrings.intro),
            const SizedBox(height: 16),
            LayoutBuilder(builder: (context, box) {
              final width =
                  box.maxWidth < 760 ? box.maxWidth : (box.maxWidth - 32) / 3;
              return Wrap(spacing: 16, runSpacing: 16, children: [
                for (final item in catalog.items)
                  SizedBox(
                      width: width,
                      child: Card(
                          clipBehavior: Clip.antiAlias,
                          child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                if (item.image != null)
                                  Image.network(item.image!,
                                      height: 120,
                                      width: double.infinity,
                                      fit: BoxFit.cover,
                                      excludeFromSemantics: true,
                                      errorBuilder: (_, __, ___) => _art(item)),
                                if (item.image == null) _art(item),
                                Padding(
                                    padding: const EdgeInsets.all(16),
                                    child: Column(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        children: [
                                          Text(DemoOccasionStrings.badge,
                                              style: Theme.of(context)
                                                  .textTheme
                                                  .labelMedium),
                                          const SizedBox(height: 8),
                                          Text(item.title,
                                              style: Theme.of(context)
                                                  .textTheme
                                                  .titleLarge),
                                          const SizedBox(height: 8),
                                          Text(item.description),
                                          const SizedBox(height: 16),
                                          FilledButton(
                                              onPressed: () => _open(item),
                                              child: Text(
                                                  DemoOccasionStrings.view))
                                        ]))
                              ]))),
              ]);
            }),
          ]
        ]));
  }

  Widget _art(DemoOccasion item) {
    final color = switch (item.key) {
      'ball' => const Color(0xff401529),
      'concert' => const Color(0xff101820),
      _ => const Color(0xff123b20),
    };
    return ExcludeSemantics(
        child: Container(
            height: 120,
            width: double.infinity,
            color: color,
            alignment: Alignment.center,
            child: Icon(
                switch (item.key) {
                  'ball' => Icons.nightlife,
                  'concert' => Icons.music_note,
                  _ => Icons.landscape
                },
                color: Colors.white,
                size: 56)));
  }
}
