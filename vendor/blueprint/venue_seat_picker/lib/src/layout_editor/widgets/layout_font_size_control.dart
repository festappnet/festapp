import 'package:material_ui/material_ui.dart';
import 'package:venue_seat_picker/venue_seat_picker.dart';
import 'layout_number_slider_control.dart';

class LayoutFontSizeControl extends StatelessWidget {
  const LayoutFontSizeControl({
    super.key,
    required this.controller,
    required this.node,
    required this.value,
    this.updateDocument,
    this.onReset,
  });
  final VenueLayoutController controller;
  final LayoutNode node;
  final double value;
  final VoidCallback? onReset;
  final VenueLayoutDocument Function(VenueLayoutDocument, double)?
  updateDocument;
  @override
  Widget build(BuildContext context) => LayoutNumberSliderControl(
    controller: controller,
    node: node,
    value: value,
    label: 'Font size',
    min: layoutLimits['fontSizeMin']!.toDouble(),
    max: layoutLimits['fontSizeMax']!.toDouble(),
    rangeMin: 8,
    rangeMax: 96,
    wholeNumbers: true,
    onReset:
        onReset ??
        () => controller.apply(
          setNodeStyleLeaf(controller.document, node.id, [
            'label',
            'size',
          ], unset: true),
          label: 'Reset font size',
        ),
    updateDocument:
        updateDocument ??
        (document, size) =>
            setNodeStyleLeaf(document, node.id, ['label', 'size'], value: size),
  );
}
