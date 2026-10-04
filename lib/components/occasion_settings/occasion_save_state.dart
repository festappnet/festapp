import 'package:auto_route/auto_route.dart';

/// Saving refreshes shared metadata without reopening the shell's default tab.
/// A renamed occasion replaces only its URL segment, retaining the deep link.
Future<void> refreshSavedOccasion({
  required StackRouter router,
  required String previousLink,
  required String savedLink,
  required Future<void> Function(String) refresh,
}) async {
  final root = router.root;
  final uri = root.urlState.uri;
  if (previousLink != savedLink &&
      uri.pathSegments.isNotEmpty &&
      uri.pathSegments.first == previousLink) {
    final target = uri.replace(pathSegments: [
      '',
      savedLink,
      ...uri.pathSegments.skip(1),
    ]).toString();
    root.markUrlStateForReplace();
    await root
        .navigateAll(root.matcher.match(target, includePrefixMatches: false)!);
  }
  await refresh(savedLink);
}

Future<void> runOccasionSaveAction({
  required Future<void> Function() action,
  required void Function(bool isSaving) setSaving,
}) async {
  setSaving(true);
  try {
    await action();
  } finally {
    setSaving(false);
  }
}
