import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:fstapp/app_config.dart';
import 'package:fstapp/services/app_logger.dart';
import 'package:fstapp/services/launch_url_service.dart';
import 'feedback_strings.dart';

class FeedbackFloatingButton extends StatefulWidget {
  const FeedbackFloatingButton({super.key});

  @override
  State<FeedbackFloatingButton> createState() => _FeedbackFloatingButtonState();
}

class _FeedbackFloatingButtonState extends State<FeedbackFloatingButton>
    with SingleTickerProviderStateMixin {
  bool _isOpen = false;
  late AnimationController _animationController;
  late Animation<double> _scaleAnimation;

  @override
  void initState() {
    super.initState();
    _animationController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 200),
    );
    _scaleAnimation = CurvedAnimation(
      parent: _animationController,
      curve: Curves.easeOut,
    );
  }

  @override
  void dispose() {
    _animationController.dispose();
    super.dispose();
  }

  void _toggleMenu() {
    setState(() {
      _isOpen = !_isOpen;
      if (_isOpen) {
        _animationController.forward();
      } else {
        _animationController.reverse();
      }
    });
  }

  void _handleOptionSelection(String subject, String bodyHint) {
    _toggleMenu();

    final fullBody =
        "$bodyHint\n\n\n---\n${FeedbackStrings.sentFrom(AppConfig.appName)}";

    showDialog(
      context: context,
      builder: (context) => _EmailOptionDialog(
        toEmail: AppConfig.feedbackEmail,
        subject: subject,
        body: fullBody,
      ),
    );
  }

  Widget _buildOptionBadge(String label, IconData icon, String subject,
      String bodyHint, Color color) {
    // Use cardColor for background to ensure it looks good in dark mode
    final bgColor = Theme.of(context).cardColor;
    final textColor = Theme.of(context).textTheme.bodyMedium?.color;

    return Padding(
      padding: const EdgeInsets.only(bottom: 8.0),
      child: InkWell(
        onTap: () => _handleOptionSelection(subject, bodyHint),
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 16),
          decoration: BoxDecoration(
            color: bgColor,
            borderRadius: BorderRadius.circular(24),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.15),
                blurRadius: 6,
                offset: const Offset(0, 3),
              ),
            ],
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              Text(
                label,
                style: TextStyle(
                    fontWeight: FontWeight.w600,
                    fontSize: 14,
                    color: textColor),
              ),
              const SizedBox(width: 8),
              Icon(icon, size: 20, color: color),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final appName = AppConfig.appName;
    final bgColor = Theme.of(context).cardColor;
    final textColor = Theme.of(context).textTheme.bodyMedium?.color;

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        if (_isOpen)
          ScaleTransition(
            scale: _scaleAnimation,
            child: Padding(
              padding: const EdgeInsets.only(bottom: 12.0, right: 4.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Container(
                    padding: const EdgeInsets.all(12),
                    margin: const EdgeInsets.only(bottom: 12),
                    decoration: BoxDecoration(
                      color: bgColor,
                      borderRadius: const BorderRadius.only(
                        topLeft: Radius.circular(16),
                        topRight: Radius.circular(16),
                        bottomLeft: Radius.circular(16),
                        bottomRight: Radius.circular(4),
                      ),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withOpacity(0.1),
                          blurRadius: 8,
                          offset: const Offset(0, 4),
                        ),
                      ],
                    ),
                    child: Text(
                      FeedbackStrings.helpTitle,
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        color: textColor,
                        fontSize: 14,
                      ),
                    ),
                  ),
                  _buildOptionBadge(
                      FeedbackStrings.requestFeature,
                      Icons.lightbulb_outline,
                      FeedbackStrings.subjectFeature(appName),
                      FeedbackStrings.hintFeature,
                      Colors.amber[700]!),
                  _buildOptionBadge(
                      FeedbackStrings.reportBug,
                      Icons.bug_report_outlined,
                      FeedbackStrings.subjectBug(appName),
                      FeedbackStrings.hintBug,
                      Colors.red[400]!),
                  _buildOptionBadge(
                      FeedbackStrings.support,
                      Icons.help_outline,
                      FeedbackStrings.subjectSupport(appName),
                      FeedbackStrings.hintSupport,
                      Colors.blue[400]!),
                  _buildOptionBadge(
                      FeedbackStrings.other,
                      Icons.chat_bubble_outline,
                      FeedbackStrings.subjectGeneral(appName),
                      FeedbackStrings.hintGeneral,
                      Colors.grey[600]!),
                ],
              ),
            ),
          ),
        FloatingActionButton(
          heroTag: "feedback_fab",
          onPressed: _toggleMenu,
          backgroundColor:
              _isOpen ? Colors.grey[200] : Theme.of(context).primaryColor,
          foregroundColor: _isOpen ? Colors.black : Colors.white,
          elevation: 4,
          shape: const CircleBorder(),
          child: AnimatedSwitcher(
            duration: const Duration(milliseconds: 200),
            transitionBuilder: (Widget child, Animation<double> animation) {
              return ScaleTransition(scale: animation, child: child);
            },
            child: Icon(
              _isOpen ? Icons.close : Icons.chat_bubble,
              key: ValueKey<bool>(_isOpen),
            ),
          ),
        ),
      ],
    );
  }
}

class _EmailOptionDialog extends StatelessWidget {
  final String toEmail;
  final String subject;
  final String body;

  const _EmailOptionDialog({
    required this.toEmail,
    required this.subject,
    required this.body,
  });

  Future<void> _launchEmail() async {
    final Uri emailLaunchUri = Uri(
      scheme: 'mailto',
      path: toEmail,
      query: _encodeQueryParameters(
          <String, String>{'subject': subject, 'body': body}),
    );

    final launched =
        await LaunchUrlService.openExternalUrl(emailLaunchUri.toString());
    if (!launched) {
      AppLogger.error("Could not launch email client");
    }
  }

  String? _encodeQueryParameters(Map<String, String> params) {
    return params.entries
        .map((e) =>
            '${Uri.encodeComponent(e.key)}=${Uri.encodeComponent(e.value)}')
        .join('&');
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final subtleColor = theme.textTheme.bodySmall?.color;

    return AlertDialog(
      insetPadding: const EdgeInsets.all(16),
      titlePadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      title: Row(
        children: [
          Expanded(child: SelectableText(FeedbackStrings.helpTitle)),
          IconButton(
            icon: const Icon(Icons.close),
            onPressed: () => Navigator.of(context).pop(),
          )
        ],
      ),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            ElevatedButton.icon(
              onPressed: _launchEmail,
              icon: const Icon(Icons.email_outlined),
              label: Text(FeedbackStrings.openEmailApp),
            ),
            const SizedBox(height: 24),

            // Manual section divider
            Row(
              children: [
                const Expanded(child: Divider()),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 8.0),
                  child: Text(
                    FeedbackStrings.manualInstructions,
                    style: TextStyle(fontSize: 12, color: subtleColor),
                  ),
                ),
                const Expanded(child: Divider()),
              ],
            ),
            const SizedBox(height: 16),

            _CopyableRow(label: FeedbackStrings.emailTo, value: toEmail),
            const SizedBox(height: 8),
            _CopyableRow(label: FeedbackStrings.emailSubject, value: subject),
            const SizedBox(height: 8),
            _CopyableRow(
                label: FeedbackStrings.emailBody, value: body, maxLines: 5),
          ],
        ),
      ),
      // No Action buttons needed at bottom as we have the close button in Title and Action button at top
    );
  }
}

class _CopyableRow extends StatelessWidget {
  final String label;
  final String value;
  final int maxLines;

  const _CopyableRow({
    required this.label,
    required this.value,
    this.maxLines = 1,
  });

  void _copy(BuildContext context) {
    Clipboard.setData(ClipboardData(text: value));
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(FeedbackStrings.copied),
        duration: const Duration(seconds: 1),
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        // Use transparent background but a border that adapts to theme (light grey or dark grey)
        border: Border.all(color: theme.dividerColor),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        crossAxisAlignment:
            maxLines > 1 ? CrossAxisAlignment.start : CrossAxisAlignment.center,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.bold,
                    color:
                        theme.textTheme.bodySmall?.color, // Subtle label color
                  ),
                ),
                const SizedBox(height: 4),
                SelectableText(
                  value,
                  maxLines: maxLines,
                  style: theme.textTheme.bodyMedium, // Standard text color
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          IconButton(
            icon: Icon(Icons.copy, size: 18, color: theme.colorScheme.primary),
            tooltip: FeedbackStrings.copyToClipboard,
            constraints: const BoxConstraints(),
            padding: const EdgeInsets.all(8),
            onPressed: () => _copy(context),
          ),
        ],
      ),
    );
  }
}
