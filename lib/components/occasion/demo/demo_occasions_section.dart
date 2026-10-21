import 'package:fstapp/components/occasion/occasion_creation_helper.dart';
import 'package:flutter/material.dart';
import 'package:fstapp/components/_shared/common_strings.dart';
import 'package:fstapp/components/occasion/demo/demo_catalog.dart';
import 'package:fstapp/components/occasion/demo/demo_occasion_strings.dart';
import 'demo_occasion_navigation.dart';
import 'package:fstapp/components/unit/views/occasion_edit_card.dart';

/// Unit administration supplies its unfiltered occasion state; the public
/// catalogue uses the account-wide metadata returned with its examples.
class DemoOccasionsSection extends StatefulWidget {
  final bool? hasOwnOccasions;
  final Future<DemoCatalog> Function() load;
  final Future<void> Function(DemoOccasion)? onOpen;
  final Future<void> Function(DemoOccasion)? onCreateCopy;
  const DemoOccasionsSection(
      {super.key,
      this.hasOwnOccasions,
      this.load = DemoCatalog.load,
      this.onOpen,
      this.onCreateCopy});
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
    if (catalog == null) return const SizedBox.shrink();
    if (catalog.items.isEmpty) return const SizedBox.shrink();
    final hasOwnOccasions = widget.hasOwnOccasions ?? catalog.hasOwnWork;
    final showCards = !hasOwnOccasions || _expanded;
    return Padding(
        padding: const EdgeInsets.all(16),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          if (hasOwnOccasions)
            TextButton.icon(
                onPressed: () => setState(() => _expanded = !_expanded),
                icon: Icon(_expanded ? Icons.expand_less : Icons.expand_more),
                label: Text(DemoOccasionStrings.heading))
          else
            Text(DemoOccasionStrings.heading,
                style: Theme.of(context).textTheme.headlineSmall),
          if (showCards) ...[
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
                  onCreateCopy: () async {
                    if (widget.onCreateCopy != null) {
                      await widget.onCreateCopy!(item);
                    } else {
                      await OccasionCreationHelper.createCopy(
                          context, item.occasion);
                    }
                    if (mounted) await _load();
                  },
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
