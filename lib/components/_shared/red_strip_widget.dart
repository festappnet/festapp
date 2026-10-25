import 'package:material_ui/material_ui.dart';
import 'package:fstapp/services/web_styles_helper.dart';
import 'package:fstapp/theme_config.dart';
import 'package:fstapp/components/html/html_view.dart';

class RedStripWidget extends StatelessWidget {
  /// The plain text or HTML content to display.
  /// If this is null or empty, the widget will not be shown.
  final String? text;

  const RedStripWidget({
    super.key,
    this.text,
  });

  @override
  Widget build(BuildContext context) {
    // Check if text is null or empty.
    // (text?.isEmpty ?? true) means:
    // 1. If text is null, the expression is true.
    // 2. If text is not null, check if it's empty (e.g., "").
    if (text?.isEmpty ?? true) {
      // Return an empty widget that takes no space.
      return const SizedBox.shrink();
    }

    // If we are here, text is valid. Build the widget as before.
    final String htmlContent = '''
      <div style="color: ${ThemeConfig.whiteColor(context).toHexString()}; text-align: center; font-size: 12px; font-weight: bold;">
        $text
      </div>
    ''';

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      // Use the red color from your app's theme_config.dart
      color: ThemeConfig.redColor(context),
      child: HtmlView(
        html: htmlContent,
        isSelectable: true,
      ),
    );
  }
}
