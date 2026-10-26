import 'package:flutter/material.dart' as sdk_material;
import 'package:material_ui/material_ui.dart';

/// Supplies the standalone UI theme and locale to dependencies that still use
/// SDK Material (TrinaGrid 2.3 and flutter_colorpicker 1.1). Remove this boundary
/// when those dependencies migrate; application widgets use material_ui only.
class DependencyMaterialBridge extends StatelessWidget {
  const DependencyMaterialBridge({super.key, required this.child});

  final Widget child;

  static Widget builder(BuildContext context, Widget? child) =>
      DependencyMaterialBridge(child: child ?? const SizedBox.shrink());

  static TransitionBuilder wrapBuilder(TransitionBuilder builder) =>
      (context, child) =>
          DependencyMaterialBridge(child: builder(context, child));

  @override
  Widget build(BuildContext context) {
    // The framework provides this utility specifically for migrating packages.
    // ignore: deprecated_member_use
    return MaterialUiCompatibilityBridge(
      child: sdk_material.Material(
        type: sdk_material.MaterialType.transparency,
        child: child,
      ),
    );
  }
}
