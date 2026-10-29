import 'package:material_ui/material_ui.dart';

/// Presentation-only navigation. Completion and visitation come from the owner.
class OccasionSetupStoryShell extends StatefulWidget {
  const OccasionSetupStoryShell({
    super.key,
    required this.questionTitles,
    required this.currentIndex,
    required this.eventTitle,
    required this.status,
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
    this.onNext,
    this.nextLabel = 'Pokračovat',
    this.allQuestionsLabel,
    this.visitedLabel = 'Rozpracováno',
    this.contextLabel,
    this.primaryAction,
    this.error,
    this.maxContentWidth = 680,
  });

  final List<String>? questionKeys;
  final List<String>? questionLabels;
  final List<int?>? questionNumbers;
  final List<String>? questionSections;
  final Set<String> completedKeys;
  final Set<String> visitedKeys;
  final ValueChanged<String>? onQuestionSelected;
  final String? allQuestionsLabel;
  final String visitedLabel;
  final String? contextLabel;
  final List<String> questionTitles;
  final int currentIndex;
  final String eventTitle;
  final String status;
  final String questionCount;

  /// Completed, current and upcoming labels, in that order.
  final List<String> segmentStates;
  final String leaveLabel;
  final String backLabel;
  final VoidCallback? onLeave;
  final VoidCallback? onBack;
  final VoidCallback? onNext;
  final String nextLabel;
  final Widget child;
  final Widget? primaryAction;
  final Widget? error;
  final double maxContentWidth;

  @override
  State<OccasionSetupStoryShell> createState() =>
      _OccasionSetupStoryShellState();
}

class _OccasionSetupStoryShellState extends State<OccasionSetupStoryShell> {
  final _headingFocus = FocusNode();

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
  void didUpdateWidget(covariant OccasionSetupStoryShell oldWidget) {
    super.didUpdateWidget(oldWidget);
    final oldKey =
        oldWidget.questionKeys?[oldWidget.currentIndex] ??
        '${oldWidget.currentIndex}';
    if (oldKey != _keyAt(widget.currentIndex)) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        _headingFocus.requestFocus();
      });
    }
  }

  @override
  void dispose() {
    _headingFocus.dispose();
    super.dispose();
  }

  Widget _questionMenu(
    int index, {
    required bool enabled,
    required Widget child,
  }) {
    if (!enabled || widget.onQuestionSelected == null) return child;
    return PopupMenuButton<String>(
      tooltip:
          widget.allQuestionsLabel ??
          MaterialLocalizations.of(context).showMenuTooltip,
      initialValue: _keyAt(index),
      onSelected: widget.onQuestionSelected,
      itemBuilder: (context) => [
        for (var target = 0; target < widget.questionTitles.length; target++)
          PopupMenuItem<String>(
            value: _keyAt(target),
            height: 48,
            child: Semantics(
              label: widget.questionTitles[target],
              selected: target == widget.currentIndex,
              child: Text('${_numberedLabelAt(target)} · ${_stateAt(target)}'),
            ),
          ),
      ],
      child: ConstrainedBox(
        constraints: const BoxConstraints(minHeight: 48),
        child: Row(
          children: [
            Expanded(child: child),
            const Icon(Icons.expand_more, size: 18),
          ],
        ),
      ),
    );
  }

  Widget _navigation(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 960),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              LayoutBuilder(
                builder: (context, constraints) {
                  final count = widget.questionTitles.length;
                  final largeText =
                      MediaQuery.textScalerOf(context).scale(14) > 21;
                  final activeWidth = (constraints.maxWidth * .48).clamp(
                    0.0,
                    220.0,
                  );
                  final interactive =
                      count == 1 ||
                      (constraints.maxWidth - activeWidth) / (count - 1) >= 48;
                  return Row(
                    key: const ValueKey('story-progress-track'),
                    children: [
                      for (var index = 0; index < count; index++)
                        if (index == widget.currentIndex)
                          SizedBox(
                            width: count == 1 || largeText
                                ? constraints.maxWidth
                                : activeWidth,
                            child: _questionMenu(
                              index,
                              enabled: !interactive || largeText,
                              child: Semantics(
                                label: widget.questionTitles[index],
                                value: _stateAt(index),
                                selected: true,
                                child: DecoratedBox(
                                  key: ValueKey(
                                    'story-target-${_keyAt(index)}',
                                  ),
                                  decoration: BoxDecoration(
                                    color: colors.primaryContainer,
                                    border: Border.all(
                                      color: colors.primary,
                                      width: 1.5,
                                    ),
                                    borderRadius: BorderRadius.circular(24),
                                  ),
                                  child: Padding(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 12,
                                      vertical: 12,
                                    ),
                                    child: Text(
                                      _numberedLabelAt(index),
                                      textAlign: TextAlign.center,
                                      style: theme.textTheme.labelLarge
                                          ?.copyWith(
                                            color: colors.onPrimaryContainer,
                                          ),
                                    ),
                                  ),
                                ),
                              ),
                            ),
                          )
                        else if (!largeText)
                          Expanded(
                            child: interactive
                                ? Semantics(
                                    label: widget.questionTitles[index],
                                    value: _stateAt(index),
                                    selected: false,
                                    child: Tooltip(
                                      message:
                                          '${_numberedLabelAt(index)} · ${_stateAt(index)}',
                                      child: OutlinedButton(
                                        key: ValueKey(
                                          'story-target-${_keyAt(index)}',
                                        ),
                                        onPressed:
                                            widget.onQuestionSelected == null
                                            ? null
                                            : () => widget.onQuestionSelected!(
                                                _keyAt(index),
                                              ),
                                        style: OutlinedButton.styleFrom(
                                          minimumSize: const Size(44, 48),
                                          padding: EdgeInsets.zero,
                                          shape: const CircleBorder(),
                                          side: BorderSide(
                                            color: colors.outlineVariant,
                                          ),
                                        ),
                                        child:
                                            widget.completedKeys.contains(
                                              _keyAt(index),
                                            )
                                            ? const Icon(Icons.check, size: 18)
                                            : widget.visitedKeys.contains(
                                                _keyAt(index),
                                              )
                                            ? const Icon(
                                                Icons.edit_outlined,
                                                size: 18,
                                              )
                                            : Text(
                                                widget.questionNumbers == null
                                                    ? '${index + 1}'
                                                    : widget.questionNumbers![index]
                                                              ?.toString() ??
                                                          '·',
                                              ),
                                      ),
                                    ),
                                  )
                                // On narrow screens the full-size menu provides every
                                // destination; the condensed track is visual progress.
                                : ExcludeSemantics(
                                    child: SizedBox(
                                      key: ValueKey(
                                        'story-marker-${_keyAt(index)}',
                                      ),
                                      height: 48,
                                      child: Center(
                                        child: Container(
                                          width: 6,
                                          height:
                                              widget.visitedKeys.contains(
                                                    _keyAt(index),
                                                  ) &&
                                                  !widget.completedKeys
                                                      .contains(_keyAt(index))
                                              ? 12
                                              : 6,
                                          decoration: BoxDecoration(
                                            color:
                                                widget.completedKeys.contains(
                                                  _keyAt(index),
                                                )
                                                ? colors.primary
                                                : null,
                                            border: Border.all(
                                              color: colors.outline,
                                            ),
                                            borderRadius: BorderRadius.circular(
                                              widget.completedKeys.contains(
                                                    _keyAt(index),
                                                  )
                                                  ? 1
                                                  : 6,
                                            ),
                                          ),
                                        ),
                                      ),
                                    ),
                                  ),
                          ),
                    ],
                  );
                },
              ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    return SafeArea(
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(24, 8, 12, 0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Tooltip(
                            message: widget.eventTitle,
                            child: Text(
                              widget.eventTitle,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: theme.textTheme.titleSmall,
                            ),
                          ),
                          if (widget.contextLabel != null)
                            Text(
                              widget.contextLabel!,
                              style: theme.textTheme.bodySmall,
                            ),
                          Text(
                            widget.status,
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: colors.onSurfaceVariant,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 8),
                    IconButton(
                      tooltip: widget.leaveLabel,
                      onPressed: widget.onLeave,
                      constraints: const BoxConstraints(
                        minWidth: 48,
                        minHeight: 48,
                      ),
                      icon: const Icon(Icons.close),
                    ),
                  ],
                ),
              ],
            ),
          ),
          Row(
            children: [
              IconButton(
                key: const ValueKey('story-previous-arrow'),
                tooltip: widget.backLabel,
                onPressed: widget.onBack,
                icon: const Icon(Icons.chevron_left),
              ),
              Expanded(child: _navigation(context)),
              IconButton(
                key: const ValueKey('story-next-arrow'),
                tooltip: widget.nextLabel,
                onPressed: widget.onNext,
                icon: const Icon(Icons.chevron_right),
              ),
            ],
          ),

          if (widget.error != null)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24),
              child: widget.error!,
            ),
          Expanded(
            child: LayoutBuilder(
              builder: (context, constraints) {
                final gutter = constraints.maxWidth < 600 ? 24.0 : 48.0;
                final verticalSpace = constraints.maxHeight < 400 ? 24.0 : 48.0;
                return SingleChildScrollView(
                  key: ValueKey(
                    'story-question-${_keyAt(widget.currentIndex)}',
                  ),
                  padding: EdgeInsets.symmetric(
                    horizontal: gutter,
                    vertical: verticalSpace,
                  ),
                  child: ConstrainedBox(
                    constraints: BoxConstraints(
                      minHeight: (constraints.maxHeight - verticalSpace * 2)
                          .clamp(0.0, double.infinity),
                    ),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.start,
                      children: [
                        Center(
                          child: ConstrainedBox(
                            constraints: BoxConstraints(
                              maxWidth: widget.maxContentWidth,
                            ),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.stretch,
                              children: [
                                Text(
                                  widget.questionCount,
                                  style: theme.textTheme.labelLarge?.copyWith(
                                    color: colors.primary,
                                  ),
                                ),
                                const SizedBox(height: 12),
                                Semantics(
                                  header: true,
                                  child: Focus(
                                    focusNode: _headingFocus,
                                    skipTraversal: true,
                                    child: Text(
                                      widget.questionTitles[widget
                                          .currentIndex],
                                      style: constraints.maxWidth < 600
                                          ? theme.textTheme.headlineSmall
                                          : theme.textTheme.headlineMedium,
                                    ),
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
              },
            ),
          ),
          // A layout sibling of the scroll view, so neither the keyboard nor
          // large text causes navigation to cover the question's controls.
          DecoratedBox(
            decoration: BoxDecoration(
              border: Border(top: BorderSide(color: colors.outlineVariant)),
            ),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(24, 12, 24, 12),
              child: Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 960),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Wrap(
                        alignment: WrapAlignment.spaceBetween,
                        crossAxisAlignment: WrapCrossAlignment.center,
                        spacing: 16,
                        children: [
                          TextButton(
                            onPressed: widget.onBack,
                            style: TextButton.styleFrom(
                              minimumSize: const Size(64, 48),
                            ),
                            child: Text(widget.backLabel),
                          ),
                          if (widget.primaryAction != null)
                            widget.primaryAction!,
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
