import 'package:flutter/foundation.dart';
import 'package:material_ui/material_ui.dart';
import 'package:fstapp/app_config.dart';
import 'package:fstapp/components/users/user_strings.dart';
import 'package:url_launcher/link.dart';

Uri resolveProfileLegalUri(
  Uri configuredUri, {
  Uri? appUri,
  bool? useLocalStaticDocument,
  bool? includeReturnTo,
}) {
  final currentAppUri = appUri ?? Uri.base;
  final isLoopback = currentAppUri.host == 'localhost' ||
      currentAppUri.host == '127.0.0.1' ||
      currentAppUri.host == '::1';
  final shouldUseLocalDocument =
      useLocalStaticDocument ?? (kIsWeb && kDebugMode && isLoopback);
  final targetUri = shouldUseLocalDocument
      ? currentAppUri.replace(
          path:
              '${configuredUri.path.endsWith('/') ? configuredUri.path : '${configuredUri.path}/'}index.html',
          query: null,
          fragment: null,
        )
      : configuredUri;

  if (!(includeReturnTo ?? kIsWeb)) return targetUri;

  final returnTo = StringBuffer(
    currentAppUri.path.isEmpty ? '/' : currentAppUri.path,
  )
    ..write(currentAppUri.hasQuery ? '?${currentAppUri.query}' : '')
    ..write(currentAppUri.hasFragment ? '#${currentAppUri.fragment}' : '');
  return targetUri.replace(
    queryParameters: {
      ...targetUri.queryParameters,
      'returnTo': returnTo.toString(),
    },
  );
}

class ProfileLegalLink extends StatelessWidget {
  const ProfileLegalLink({
    super.key,
    required this.label,
    required this.uri,
  });

  final String label;
  final Uri uri;

  @override
  Widget build(BuildContext context) {
    final targetUri = resolveProfileLegalUri(uri);
    return Link(
      uri: targetUri,
      target: LinkTarget.self,
      builder: (context, followLink) => TextButton(
        onPressed: followLink,
        style: TextButton.styleFrom(
          foregroundColor: Theme.of(context).colorScheme.onSurfaceVariant,
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          minimumSize: const Size(0, 36),
          textStyle: Theme.of(context).textTheme.bodySmall,
        ),
        child: Text(label, textAlign: TextAlign.center),
      ),
    );
  }
}

/// One canonical, public set of legal and support links for signed-in and
/// signed-out surfaces.
class AppLegalLinks extends StatelessWidget {
  const AppLegalLinks({
    super.key,
    this.overrideUris,
  });

  final List<Uri>? overrideUris;

  @override
  Widget build(BuildContext context) {
    final configuredUris = overrideUris ??
        <Uri>[
          Uri.parse(AppConfig.privacyUrl),
          Uri.parse(AppConfig.privacyChoicesUrl),
          Uri.parse(AppConfig.termsUrl),
          Uri.parse(AppConfig.supportUrl),
        ];
    assert(configuredUris.length == 4);
    final links = <({String label, Uri uri})>[
      (
        label: UserStrings.privacy,
        uri: configuredUris[0],
      ),
      (
        label: UserStrings.privacyChoices,
        uri: configuredUris[1],
      ),
      (
        label: UserStrings.terms,
        uri: configuredUris[2],
      ),
      (
        label: UserStrings.support,
        uri: configuredUris[3],
      ),
    ];

    return Wrap(
      alignment: WrapAlignment.center,
      spacing: 2,
      runSpacing: 0,
      children: [
        for (final link in links)
          ProfileLegalLink(
            label: link.label,
            uri: link.uri,
          ),
      ],
    );
  }
}
