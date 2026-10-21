import 'package:flutter/material.dart';
import 'package:fstapp/widgets/app_dialog.dart';

/// One journey position, with an explicitly named jump list on every screen.
class OccasionSetupStoryShell extends StatelessWidget {
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
    this.onQuestionSelected,
    required this.child,
    this.primaryAction,
    this.error,
    this.maxContentWidth = 680,
    this.centerQuestion = true,
  });

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
  final ValueChanged<int>? onQuestionSelected;
  final Widget child;
  final Widget? primaryAction;
  final Widget? error;
  final double maxContentWidth;
  final bool centerQuestion;

  void _showQuestions(BuildContext context) {
    showDialog<void>(
        context: context,
        builder: (dialogContext) => AppSimpleDialog(
              title: Text(questionCount),
              children: [
                for (var index = 0; index < questionTitles.length; index++)
                  ListTile(
                    leading: Text('${index + 1}'),
                    title: Text(questionTitles[index]),
                    selected: index == currentIndex,
                    onTap: onQuestionSelected == null
                        ? null
                        : () {
                            Navigator.of(dialogContext).pop();
                            onQuestionSelected!(index);
                          },
                  ),
              ],
            ));
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    return SafeArea(
      child: Column(children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
          child: Row(children: [
            for (var index = 0; index < questionTitles.length; index++) ...[
              if (index > 0) const SizedBox(width: 4),
              Expanded(
                child: Semantics(
                  label: questionTitles[index],
                  value: segmentStates[index < currentIndex
                      ? 0
                      : index == currentIndex
                          ? 1
                          : 2],
                  selected: index == currentIndex,
                  button: onQuestionSelected != null,
                  enabled: onQuestionSelected != null,
                  onTap: onQuestionSelected == null
                      ? null
                      : () => onQuestionSelected!(index),
                  child: Tooltip(
                    message: questionTitles[index],
                    excludeFromSemantics: true,
                    child: InkWell(
                      excludeFromSemantics: true,
                      onTap: onQuestionSelected == null
                          ? null
                          : () => onQuestionSelected!(index),
                      borderRadius: BorderRadius.circular(4),
                      child: SizedBox(
                        height: 44,
                        child: Center(
                          child: Container(
                            height: index == currentIndex ? 6 : 3,
                            decoration: BoxDecoration(
                              color: index <= currentIndex
                                  ? colors.primary
                                  : colors.outline,
                              borderRadius: BorderRadius.circular(4),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ]),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(24, 8, 12, 0),
          child: Row(children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Tooltip(
                    message: eventTitle,
                    child: Text(eventTitle,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.titleSmall),
                  ),
                  Text(status,
                      style: theme.textTheme.bodySmall
                          ?.copyWith(color: colors.onSurfaceVariant)),
                ],
              ),
            ),
            const SizedBox(width: 8),
            IconButton(
              tooltip: leaveLabel,
              onPressed: onLeave,
              constraints: const BoxConstraints(minWidth: 48, minHeight: 48),
              icon: const Icon(Icons.close),
            ),
          ]),
        ),
        if (error != null)
          Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24),
              child: error!),
        Expanded(
          child: LayoutBuilder(builder: (context, constraints) {
            final gutter = constraints.maxWidth < 600 ? 24.0 : 48.0;
            final verticalSpace = constraints.maxHeight < 400 ? 24.0 : 48.0;
            return SingleChildScrollView(
              key: ValueKey('story-question-$currentIndex'),
              padding: EdgeInsets.symmetric(
                  horizontal: gutter, vertical: verticalSpace),
              child: ConstrainedBox(
                constraints: BoxConstraints(
                    minHeight: (constraints.maxHeight - verticalSpace * 2)
                        .clamp(0.0, double.infinity)),
                child: Column(
                  mainAxisAlignment: centerQuestion
                      ? MainAxisAlignment.center
                      : MainAxisAlignment.start,
                  children: [
                    Center(
                      child: ConstrainedBox(
                        constraints: BoxConstraints(maxWidth: maxContentWidth),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            Align(
                              alignment: AlignmentDirectional.centerStart,
                              child: TextButton.icon(
                                onPressed: onQuestionSelected == null
                                    ? null
                                    : () => _showQuestions(context),
                                icon: const Icon(Icons.format_list_numbered,
                                    size: 18),
                                label: Text(questionCount),
                              ),
                            ),
                            const SizedBox(height: 12),
                            Semantics(
                              header: true,
                              child: Text(questionTitles[currentIndex],
                                  style: constraints.maxWidth < 600
                                      ? theme.textTheme.headlineSmall
                                      : theme.textTheme.headlineMedium),
                            ),
                            const SizedBox(height: 32),
                            child,
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
                  Row(children: [
                    TextButton(
                      onPressed: onBack,
                      style:
                          TextButton.styleFrom(minimumSize: const Size(64, 48)),
                      child: Text(backLabel),
                    ),
                    const SizedBox(width: 16),
                    Expanded(
                      child: Align(
                        alignment: Alignment.centerRight,
                        child: primaryAction,
                      ),
                    ),
                  ]),
                ]),
              ),
            ),
          ),
        ),
      ]),
    );
  }
}
