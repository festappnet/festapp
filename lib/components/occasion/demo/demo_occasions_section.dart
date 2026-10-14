import 'package:flutter/material.dart';
import 'package:fstapp/components/_shared/common_strings.dart';
import 'package:fstapp/components/occasion/demo/demo_catalog.dart';
import 'package:fstapp/components/occasion/demo/demo_occasion_strings.dart';
import 'demo_occasion_navigation.dart';
import 'package:fstapp/components/unit/views/occasion_edit_card.dart';

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
      await DemoOccasionNavigation.open(context, item.link);
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
            GridView.builder(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
                maxCrossAxisExtent: 420,
                mainAxisExtent: 110,
                mainAxisSpacing: 16,
                crossAxisSpacing: 16,
              ),
              itemCount: catalog.items.length,
              itemBuilder: (context, index) {
                final item = catalog.items[index];
                final theme = Theme.of(context);
                final base = theme.brightness == Brightness.dark
                    ? Colors.grey[850]!
                    : theme.cardColor;
                return OccasionEditCard(
                  occasion: item.occasion,
                  onTap: () => _open(item),
                  viewLabel: DemoOccasionStrings.view,
                  badge: DemoOccasionStrings.badge,
                  backgroundColor: Color.alphaBlend(
                      theme.colorScheme.primary.withValues(alpha: .06), base),
                );
              },
            ),
          ]
        ]));
  }
}
