import 'package:material_ui/material_ui.dart';

/// Reveal a section within the editor without moving horizontal tab viewports.
void revealEditorTarget(
  BuildContext context, {
  ScrollController? controller,
  double alignment = 0,
}) {
  if (controller != null && !controller.hasClients) return;
  final owner = controller?.position;
  final target = context.findRenderObject();
  if (target == null || !target.attached) return;

  var scrollable = Scrollable.maybeOf(context, axis: Axis.vertical);
  while (scrollable != null) {
    final object = context.findRenderObject();
    if (object == null || !object.attached) return;
    scrollable.position.ensureVisible(
      object,
      targetRenderObject: target,
      alignment: alignment,
      duration: const Duration(milliseconds: 250),
      curve: Curves.easeInOut,
    );
    if (identical(scrollable.position, owner)) return;
    context = scrollable.context;
    scrollable = Scrollable.maybeOf(context, axis: Axis.vertical);
  }
}
