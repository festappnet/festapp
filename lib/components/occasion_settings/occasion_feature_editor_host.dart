import 'package:material_ui/material_ui.dart';

import '../_shared/editor_draft_scope.dart';
import '../features/feature.dart';
import 'occasion_features_controller.dart';

/// A keyed, persistent sibling of grid rows, even when hidden or regrouped.
class OccasionFeatureEditorHost extends StatefulWidget {
  final Feature feature;
  final OccasionFeaturesController controller;
  final bool visible;
  final Widget child;
  const OccasionFeatureEditorHost({
    super.key,
    required this.feature,
    required this.controller,
    required this.visible,
    required this.child,
  });
  @override
  State<OccasionFeatureEditorHost> createState() =>
      _OccasionFeatureEditorHostState();
}

class _OccasionFeatureEditorHostState extends State<OccasionFeatureEditorHost> {
  final _form = GlobalKey<FormState>();
  @override
  void initState() {
    super.initState();
    widget.controller.register(widget.feature, _form);
  }

  @override
  void dispose() {
    widget.controller.unregister(widget.feature.code, _form);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Offstage(
    offstage: !widget.visible,
    child: TickerMode(
      enabled: widget.visible,
      child: ExcludeFocus(
        excluding: !widget.visible,
        child: Form(
          key: _form,
          onChanged: () => EditorDraftScope.changed(context),
          child: widget.child,
        ),
      ),
    ),
  );
}
