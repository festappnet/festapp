import 'package:flutter/material.dart';
import 'package:fstapp/router_service.dart';
import 'package:fstapp/components/users/views/login_page.dart';
import 'package:fstapp/components/users/user_strings.dart';
import 'package:fstapp/services/google_auth_service.dart';

class GoogleAccountLinkSetting extends StatefulWidget {
  const GoogleAccountLinkSetting({super.key});
  @override
  State<GoogleAccountLinkSetting> createState() =>
      _GoogleAccountLinkSettingState();
}

class _GoogleAccountLinkSettingState extends State<GoogleAccountLinkSetting> {
  late final Future<Map<String, dynamic>> _status =
      GoogleAuthService.identityStatus();
  @override
  Widget build(BuildContext context) => FutureBuilder<Map<String, dynamic>>(
      future: _status,
      builder: (context, snapshot) {
        if (snapshot.data?['enabled'] != true) return const SizedBox.shrink();
        final linked = snapshot.data?['linked'] == true;
        return ListTile(
            leading: const Icon(Icons.link),
            title: Text(
                linked ? UserStrings.googleUnlink : UserStrings.googleContinue),
            onTap: () {
              GoogleAuthService.start(intent: linked ? 'unlink' : 'login');
              RouterService.navigate(context, LoginPage.ROUTE);
            });
      });
}
