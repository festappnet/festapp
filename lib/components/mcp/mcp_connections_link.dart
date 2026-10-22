import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:url_launcher/link.dart';

/// Account grants are managed by the issuer, independently of event roles.
class McpConnectionsLink extends StatelessWidget {
  const McpConnectionsLink({super.key});

  @override
  Widget build(BuildContext context) => Link(
        uri: Uri.parse('https://mcp.festapp.net/connections'),
        target: LinkTarget.blank,
        builder: (context, followLink) => ListTile(
          leading: const Icon(Icons.extension_outlined),
          title: Text('McpConnection.manageConnections'.tr()),
          subtitle: Text('McpConnection.manageConnectionsHint'.tr()),
          trailing: const Icon(Icons.open_in_new, size: 20),
          onTap: followLink,
        ),
      );
}
