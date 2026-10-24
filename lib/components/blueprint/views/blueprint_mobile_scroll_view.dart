import 'package:flutter/material.dart';

import '../blueprint_strings.dart';

/// Keeps the canvas mounted while exposing the editor panels at phone width.
class BlueprintMobileScrollView extends StatefulWidget {
  final Widget leftPanel;
  final Widget mainContent;
  final Widget rightPanel;
  final double screenWidth;

  const BlueprintMobileScrollView({
    super.key,
    required this.leftPanel,
    required this.mainContent,
    required this.rightPanel,
    required this.screenWidth,
  });

  @override
  State<BlueprintMobileScrollView> createState() =>
      _BlueprintMobileScrollViewState();
}

class _BlueprintMobileScrollViewState extends State<BlueprintMobileScrollView> {
  int _panel = 0;

  @override
  Widget build(BuildContext context) => Column(
        children: [
          Expanded(
            child: IndexedStack(
              index: _panel,
              sizing: StackFit.expand,
              children: [
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 8),
                  child: widget.mainContent,
                ),
                SingleChildScrollView(
                  padding: const EdgeInsets.all(16),
                  child: widget.leftPanel,
                ),
                Padding(
                  padding: const EdgeInsets.all(16),
                  child: widget.rightPanel,
                ),
              ],
            ),
          ),
          NavigationBar(
            height: 64,
            selectedIndex: _panel,
            onDestinationSelected: (value) => setState(() => _panel = value),
            destinations: [
              NavigationDestination(
                key: const ValueKey('blueprint-plan'),
                icon: const Icon(Icons.grid_on),
                label: BlueprintStrings.plan,
              ),
              NavigationDestination(
                key: const ValueKey('blueprint-tools'),
                icon: const Icon(Icons.touch_app_outlined),
                label: BlueprintStrings.editingTools,
              ),
              NavigationDestination(
                key: const ValueKey('blueprint-groups'),
                icon: const Icon(Icons.table_restaurant_outlined),
                label: BlueprintStrings.groups,
              ),
            ],
          ),
        ],
      );
}
