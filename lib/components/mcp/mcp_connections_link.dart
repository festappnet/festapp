import 'package:fstapp/components/_shared/common_strings.dart';
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
          title: Text(CommonStrings.manageConnections),
          subtitle: Text(CommonStrings.manageConnectionsHint),
          trailing: const Icon(Icons.open_in_new, size: 20),
          onTap: followLink,
        ),
      );
}
