import 'package:flutter/material.dart';

/// Presentation-only navigation. Completion and visitation come from the owner.
class OccasionSetupStoryShell extends StatefulWidget {
  const OccasionSetupStoryShell({
    super.key,
    required this.questionTitles,
    required this.currentIndex,
    required this.eventTitle,
    required this.status,
    required this.readiness,
    required this.questionCount,
    required this.segmentStates,
    required this.leaveLabel,
    required this.backLabel,
    required this.onLeave,
    required this.onBack,
    required this.child,
    this.questionKeys,
    this.questionLabels,
    this.questionNumbers,
    this.questionSections,
    this.completedKeys = const {},
    this.visitedKeys = const {},
    this.onQuestionSelected,
    this.allQuestionsLabel = 'Všechny otázky',
    this.visitedLabel = 'Rozpracováno',
    this.contextLabel,
    this.introductionAction,
    this.primaryAction,
    this.error,
    this.maxContentWidth = 680,
    this.centerQuestion = true,
  });

  final List<String>? questionKeys;
  final List<String>? questionLabels;
  final List<int?>? questionNumbers;
  final List<String>? questionSections;
  final Set<String> completedKeys;
  final Set<String> visitedKeys;
  final ValueChanged<String>? onQuestionSelected;
  final String allQuestionsLabel;
  final String visitedLabel;
  final String? contextLabel;
  final Widget? introductionAction;
  final List<String> questionTitles;
  final int currentIndex;
  final String eventTitle;
  final String status;
  final String readiness;
  final String questionCount;

  /// Completed, current and upcoming labels, in that order.
  final List<String> segmentStates;
  final String leaveLabel;
  final String backLabel;
  final VoidCallback? onLeave;
  final VoidCallback? onBack;
  final Widget child;
  final Widget? primaryAction;
  final Widget? error;
  final double maxContentWidth;
  final bool centerQuestion;

  @override
  State<OccasionSetupStoryShell> createState() =>
      _OccasionSetupStoryShellState();
}

class _OccasionSetupStoryShellState extends State<OccasionSetupStoryShell> {
  final _headingFocus = FocusNode();
  final _currentTarget = GlobalKey();

  String _keyAt(int index) => widget.questionKeys?[index] ?? '$index';
  String _labelAt(int index) =>
      widget.questionLabels?[index] ?? widget.questionTitles[index];
  String _numberedLabelAt(int index) {
    final number = widget.questionNumbers == null
        ? index + 1
        : widget.questionNumbers![index];
    return number == null ? _labelAt(index) : '$number ${_labelAt(index)}';
  }

  String _stateAt(int index) {
    if (index == widget.currentIndex) return widget.segmentStates[1];
    if (widget.completedKeys.contains(_keyAt(index)))
      return widget.segmentStates[0];
    if (widget.visitedKeys.contains(_keyAt(index))) return widget.visitedLabel;
    return widget.segmentStates[2];
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final target = _currentTarget.currentContext;
      if (target != null) Scrollable.ensureVisible(target, alignment: 0.5);
    });
  }

  @override
  void didUpdateWidget(covariant OccasionSetupStoryShell oldWidget) {
    super.didUpdateWidget(oldWidget);
    final oldKey = oldWidget.questionKeys?[oldWidget.currentIndex] ??
        '${oldWidget.currentIndex}';
    if (oldKey != _keyAt(widget.currentIndex)) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        _headingFocus.requestFocus();
        final target = _currentTarget.currentContext;
        if (target != null) Scrollable.ensureVisible(target, alignment: 0.5);
      });
    }
  }

  @override
  void dispose() {
    _headingFocus.dispose();
    super.dispose();
  }

  Widget _navigation(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final compact = MediaQuery.textScalerOf(context).scale(16) > 24;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Expanded(
              child: Text(
                  [
                    if (widget.questionSections != null)
                      widget.questionSections![widget.currentIndex],
                    _labelAt(widget.currentIndex),
                  ].join(' · '),
                  style: Theme.of(context).textTheme.labelLarge)),
          PopupMenuButton<String>(
            tooltip: widget.allQuestionsLabel,
            onSelected: widget.onQuestionSelected,
            itemBuilder: (context) => [
              for (var index = 0;
                  index < widget.questionTitles.length;
                  index++) ...[
                if (widget.questionSections != null &&
                    (index == 0 ||
                        widget.questionSections![index] !=
                            widget.questionSections![index - 1]))
                  PopupMenuItem<String>(
                      enabled: false,
                      child: Text(widget.questionSections![index],
                          style: Theme.of(context).textTheme.labelLarge)),
                PopupMenuItem<String>(
                  value: _keyAt(index),
                  child:
                      Text('${_numberedLabelAt(index)} · ${_stateAt(index)}'),
                ),
              ],
            ],
            icon: const Icon(Icons.list_alt),
          ),
        ]),
        if (!compact)
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(children: [
              for (var index = 0; index < widget.questionTitles.length; index++)
                Padding(
                  key: index == widget.currentIndex ? _currentTarget : null,
                  padding: const EdgeInsetsDirectional.only(end: 8),
                  child: Semantics(
                    label: widget.questionTitles[index],
                    value: _stateAt(index),
                    selected: index == widget.currentIndex,
                    child: OutlinedButton(
                      key: ValueKey('story-target-${_keyAt(index)}'),
                      onPressed: widget.onQuestionSelected == null
                          ? null
                          : () => widget.onQuestionSelected!(_keyAt(index)),
                      style: OutlinedButton.styleFrom(
                        minimumSize: const Size(48, 48),
                        backgroundColor: index == widget.currentIndex
                            ? colors.primaryContainer
                            : null,
                        side: BorderSide(
                            color: index == widget.currentIndex
                                ? colors.primary
                                : colors.outline,
                            width: index == widget.currentIndex ? 2 : 1),
                      ),
                      child: Row(mainAxisSize: MainAxisSize.min, children: [
                        if (widget.completedKeys.contains(_keyAt(index))) ...[
                          const Icon(Icons.check, size: 18),
                          const SizedBox(width: 4),
                        ],
                        Text(_numberedLabelAt(index)),
                        if (widget.visitedKeys.contains(_keyAt(index)) &&
                            !widget.completedKeys.contains(_keyAt(index)) &&
                            index != widget.currentIndex) ...[
                          const SizedBox(width: 4),
                          Tooltip(
                              message: widget.visitedLabel,
                              child: const Icon(Icons.edit_outlined, size: 16)),
                        ],
                      ]),
                    ),
                  ),
                ),
            ]),
          ),
        if (widget.introductionAction != null) widget.introductionAction!,
      ]),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    return SafeArea(
      child: Column(children: [
        _navigation(context),
        Padding(
          padding: const EdgeInsets.fromLTRB(24, 8, 12, 0),
          child: Row(children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Tooltip(
                    message: widget.eventTitle,
                    child: Text(widget.eventTitle,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.titleSmall),
                  ),
                  if (widget.contextLabel != null)
                    Text(widget.contextLabel!,
                        style: theme.textTheme.bodySmall),
                  Text(widget.status,
                      style: theme.textTheme.bodySmall
                          ?.copyWith(color: colors.onSurfaceVariant)),
                ],
              ),
            ),
            const SizedBox(width: 8),
            IconButton(
              tooltip: widget.leaveLabel,
              onPressed: widget.onLeave,
              constraints: const BoxConstraints(minWidth: 48, minHeight: 48),
              icon: const Icon(Icons.close),
            ),
          ]),
        ),
        if (widget.error != null)
          Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24),
              child: widget.error!),
        Expanded(
          child: LayoutBuilder(builder: (context, constraints) {
            final gutter = constraints.maxWidth < 600 ? 24.0 : 48.0;
            final verticalSpace = constraints.maxHeight < 400 ? 24.0 : 48.0;
            return SingleChildScrollView(
              key: ValueKey('story-question-${_keyAt(widget.currentIndex)}'),
              padding: EdgeInsets.symmetric(
                  horizontal: gutter, vertical: verticalSpace),
              child: ConstrainedBox(
                constraints: BoxConstraints(
                    minHeight: (constraints.maxHeight - verticalSpace * 2)
                        .clamp(0.0, double.infinity)),
                child: Column(
                  mainAxisAlignment: widget.centerQuestion
                      ? MainAxisAlignment.center
                      : MainAxisAlignment.start,
                  children: [
                    Center(
                      child: ConstrainedBox(
                        constraints:
                            BoxConstraints(maxWidth: widget.maxContentWidth),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            Text(widget.questionCount,
                                style: theme.textTheme.labelLarge
                                    ?.copyWith(color: colors.primary)),
                            const SizedBox(height: 12),
                            Semantics(
                              header: true,
                              child: Focus(
                                focusNode: _headingFocus,
                                skipTraversal: true,
                                child: Text(
                                    widget.questionTitles[widget.currentIndex],
                                    style: constraints.maxWidth < 600
                                        ? theme.textTheme.headlineSmall
                                        : theme.textTheme.headlineMedium),
                              ),
                            ),
                            const SizedBox(height: 32),
                            widget.child,
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            );
          }),
        ),
        // A layout sibling of the scroll view, so neither the keyboard nor
        // large text causes navigation to cover the question's controls.
        DecoratedBox(
          decoration: BoxDecoration(
              border: Border(top: BorderSide(color: colors.outlineVariant))),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(24, 12, 24, 12),
            child: Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 960),
                child: Column(mainAxisSize: MainAxisSize.min, children: [
                  Wrap(
                      alignment: WrapAlignment.spaceBetween,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      spacing: 16,
                      children: [
                        TextButton(
                          onPressed: widget.onBack,
                          style: TextButton.styleFrom(
                              minimumSize: const Size(64, 48)),
                          child: Text(widget.backLabel),
                        ),
                        if (widget.primaryAction != null) widget.primaryAction!,
                      ]),
                  const SizedBox(height: 4),
                  Text(widget.readiness,
                      textAlign: TextAlign.center,
                      style: theme.textTheme.bodySmall
                          ?.copyWith(color: colors.onSurfaceVariant)),
                ]),
              ),
            ),
          ),
        ),
      ]),
    );
  }
}
