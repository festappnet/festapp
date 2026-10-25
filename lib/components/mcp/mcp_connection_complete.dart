import 'package:easy_localization/easy_localization.dart';
import 'package:material_ui/material_ui.dart';
import 'package:fstapp/app_config.dart';
import 'package:url_launcher/url_launcher.dart';
import 'mcp_callback_browser.dart';

/// Completion belongs to the tenant; OAuth callback transport belongs to the client.
class McpConnectionComplete extends StatelessWidget {
  const McpConnectionComplete(
      {super.key, required this.client, required this.email});
  final String client;
  final String email;
  String text(String key) => 'McpConnection.$key'.tr();
  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    return Column(mainAxisSize: MainAxisSize.min, children: [
      Container(
          width: 88,
          height: 88,
          decoration: BoxDecoration(
              color: colors.primaryContainer, shape: BoxShape.circle),
          child: Icon(Icons.check_rounded,
              size: 48, color: colors.onPrimaryContainer)),
      const SizedBox(height: 28),
      Semantics(
          liveRegion: true,
          header: true,
          child: Text(text('connected'),
              textAlign: TextAlign.center,
              style: theme.textTheme.headlineLarge
                  ?.copyWith(fontWeight: FontWeight.w600))),
      const SizedBox(height: 16),
      Text(text('connectedClient').replaceAll('{client}', client),
          textAlign: TextAlign.center, style: theme.textTheme.titleLarge),
      const SizedBox(height: 8),
      Text(email,
          textAlign: TextAlign.center, style: theme.textTheme.bodyLarge),
      const SizedBox(height: 24),
      Text(text('closeHint'),
          textAlign: TextAlign.center, style: theme.textTheme.bodyLarge),
      const SizedBox(height: 32),
      FilledButton(
          onPressed: closeMcpConfirmationWindow,
          child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
              child: Text(text('closeWindow')))),
      const SizedBox(height: 12),
      TextButton(
          onPressed: () => launchUrl(Uri.parse(AppConfig.webLink),
              webOnlyWindowName: '_self'),
          child: Text(
              text('backToTenant').replaceAll('{tenant}', AppConfig.appName))),
    ]);
  }
}
