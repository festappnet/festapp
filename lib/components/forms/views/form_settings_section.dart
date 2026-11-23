import 'package:material_ui/material_ui.dart';

/// Keep fields registered with the surrounding Form while a section is closed.
class FormSettingsSection extends StatefulWidget {
  const FormSettingsSection({
    super.key,
    required this.title,
    required this.children,
    this.controller,
    this.summary,
    this.onExpansionChanged,
  });

  final String title;
  final String? summary;
  final List<Widget> children;
  final ExpansibleController? controller;
  final ValueChanged<bool>? onExpansionChanged;

  @override
  State<FormSettingsSection> createState() => _FormSettingsSectionState();
}

class _FormSettingsSectionState extends State<FormSettingsSection> {
  late final _ownedController = ExpansibleController();
  ExpansibleController get _controller => widget.controller ?? _ownedController;

  @override
  void dispose() {
    if (widget.controller == null) _ownedController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: _controller,
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: widget.children,
    ),
    builder: (context, child) => ExpansionTile(
      controller: _controller,
      maintainState: true,
      expansionAnimationStyle: AnimationStyle.noAnimation,
      tilePadding: EdgeInsets.zero,
      shape: const Border(),
      collapsedShape: const Border(),
      childrenPadding: const EdgeInsets.only(top: 12, bottom: 16),
      expandedCrossAxisAlignment: CrossAxisAlignment.stretch,
      onExpansionChanged: widget.onExpansionChanged,
      title: Semantics(
        expanded: _controller.isExpanded,
        child: Text(widget.title),
      ),
      subtitle: widget.summary == null ? null : Text(widget.summary!),
      children: [
        ExcludeFocus(excluding: !_controller.isExpanded, child: child!),
      ],
    ),
  );
}
