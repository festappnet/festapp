import 'package:flutter/material.dart';

/// Shared occasion navigation chrome. Routing, login and modal actions belong
/// to the retained occasion shell, so a tap also reaches it on reselection.
class OccasionNavigationBar extends StatelessWidget {
  final int selectedIndex;
  final List<NavigationDestination> destinations;
  final ValueChanged<int> onDestinationSelected;
  final bool suppressSelection;

  const OccasionNavigationBar({
    super.key,
    required this.selectedIndex,
    required this.destinations,
    required this.onDestinationSelected,
    this.suppressSelection = false,
  });

  @override
  Widget build(BuildContext context) {
    final theme = NavigationBarTheme.of(context);
    final bar = NavigationBar(
      selectedIndex: selectedIndex,
      destinations: destinations,
      onDestinationSelected: onDestinationSelected,
      // Search can be deep-linked, but is a modal action rather than a section.
      indicatorColor: suppressSelection ? Colors.transparent : null,
      labelTextStyle: suppressSelection
          ? WidgetStatePropertyAll(
              theme.labelTextStyle?.resolve(const <WidgetState>{}),
            )
          : null,
    );
    if (!suppressSelection) return bar;
    return NavigationBarTheme(
      data: theme.copyWith(
        iconTheme: WidgetStatePropertyAll(
          theme.iconTheme?.resolve(const <WidgetState>{}),
        ),
      ),
      child: bar,
    );
  }
}
