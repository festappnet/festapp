import 'package:fstapp/components/_shared/common_strings.dart';
import 'package:material_ui/material_ui.dart';
import 'package:fstapp/app_config.dart';
import 'package:url_launcher/link.dart';

/// One tenant-owned web surface for login identities and delegated app access.
class AccountConnectionsLink extends StatelessWidget {
  const AccountConnectionsLink({super.key});

  @override
  Widget build(BuildContext context) => Link(
        uri: Uri.parse(AppConfig.webLink).resolve('/settings/connections'),
        target: LinkTarget.blank,
        builder: (context, followLink) => ListTile(
          leading: const Icon(Icons.extension_outlined),
          title: Text(CommonStrings.accountConnections),
          subtitle: Text(CommonStrings.accountConnectionsHint),
          trailing: const Icon(Icons.open_in_new, size: 20),
          onTap: followLink,
        ),
      );
}
