import 'package:flutter/material.dart';

import '../../_shared/common_strings.dart';

/// Editor feedback floats above the bottom edge without moving the canvas.
class BlueprintEditorFeedback extends StatelessWidget {
  const BlueprintEditorFeedback({
    super.key,
    required this.child,
    required this.message,
    required this.onDismiss,
  });
  final Widget child;
  final String? message;
  final VoidCallback onDismiss;

  @override
  Widget build(BuildContext context) => Stack(
        children: [
          Positioned.fill(child: child),
          if (message != null)
            Positioned(
              left: 16,
              right: 16,
              bottom: 16,
              child: Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 600),
                  child: Semantics(
                    liveRegion: true,
                    child: Material(
                      key: const ValueKey('blueprint-editor-feedback'),
                      elevation: 6,
                      color: Theme.of(context).colorScheme.errorContainer,
                      borderRadius: BorderRadius.circular(12),
                      child: Padding(
                        padding: const EdgeInsets.only(left: 16, right: 4),
                        child: Row(
                          children: [
                            Expanded(
                              child: Padding(
                                padding:
                                    const EdgeInsets.symmetric(vertical: 12),
                                child: Text(
                                  message!,
                                  style: TextStyle(
                                    color: Theme.of(context)
                                        .colorScheme
                                        .onErrorContainer,
                                  ),
                                ),
                              ),
                            ),
                            IconButton(
                              tooltip: CommonStrings.close,
                              color: Theme.of(context)
                                  .colorScheme
                                  .onErrorContainer,
                              onPressed: onDismiss,
                              icon: const Icon(Icons.close),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
        ],
      );
}
