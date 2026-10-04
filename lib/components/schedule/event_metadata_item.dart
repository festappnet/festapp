import 'package:flutter/material.dart';

/// Header metadata wraps in the expanded banner and stays intrinsic-width in
/// the compact banner's horizontal scroll view.
class EventMetadataItem extends StatelessWidget {
  final IconData icon;
  final String text;
  final Color color;
  final double iconSize;
  final double fontSize;
  final bool isLink;

  const EventMetadataItem({
    super.key,
    required this.icon,
    required this.text,
    required this.color,
    this.iconSize = 20,
    this.fontSize = 15,
    this.isLink = false,
  });

  @override
  Widget build(BuildContext context) => Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, color: color, size: iconSize),
          const SizedBox(width: 6),
          Flexible(
            child: Text(
              text,
              style: TextStyle(
                color: color,
                fontWeight: FontWeight.bold,
                fontSize: fontSize,
                decoration: isLink ? TextDecoration.underline : null,
                decorationColor: isLink ? color.withValues(alpha: 0.7) : null,
                decorationThickness: isLink ? 2 : null,
              ),
            ),
          ),
          if (isLink) ...[
            const SizedBox(width: 2),
            Icon(Icons.chevron_right, color: color, size: iconSize),
          ],
        ],
      );
}
