import 'package:flutter/material.dart';

import 'package:fstapp/components/_shared/common_strings.dart';

class StandardDialog extends StatelessWidget {
  final Widget content;
  final double maxWidth;
  final VoidCallback? onClose;

  const StandardDialog({
    super.key,
    required this.content,
    this.maxWidth = 600,
    this.onClose,
  });

  @override
  Widget build(BuildContext context) {
    return Dialog(
      elevation: 16,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12.0),
        side: BorderSide(color: Colors.white.withOpacity(0.2)),
      ),
      child: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: maxWidth, minHeight: 120),
        child: Padding(
          padding: const EdgeInsets.all(16.0),
          child: Stack(
            children: [
              content,
              Positioned(
                top: 0,
                right: 0,
                child: IconButton(
                  icon: Icon(
                    Icons.close,
                    size: 24,
                    color: Theme.of(context).iconTheme.color?.withOpacity(0.8),
                  ),
                  splashRadius: 20,
                  onPressed: onClose ?? () => Navigator.of(context).pop(),
                  tooltip: CommonStrings.close,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
