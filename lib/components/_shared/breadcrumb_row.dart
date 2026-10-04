import 'package:flutter/material.dart';

/// Keeps breadcrumb labels aligned when regular and bold fonts have different metrics.
class BreadcrumbRow extends StatelessWidget {
  const BreadcrumbRow({super.key, required this.children});
  final List<Widget> children;

  @override
  Widget build(BuildContext context) => Row(
        crossAxisAlignment: CrossAxisAlignment.baseline,
        textBaseline: TextBaseline.alphabetic,
        children: children,
      );
}
