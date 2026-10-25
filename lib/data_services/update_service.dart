import 'package:material_ui/material_ui.dart';
import 'package:fstapp/components/_shared/common_strings.dart';
import 'package:fstapp/components/organization/organization_model.dart';
import 'package:fstapp/services/launch_url_service.dart';
import 'package:fstapp/services/platform_helper.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:fstapp/services/dialog_helper.dart';

class UpdateService {
  static List<PlatformModel> _platforms = const [];
  static String _configurationSignature = '';
  static bool alreadyChecked = false;
  static Future<void>? _pendingCheck;

  static void configurePlatforms(List<PlatformModel>? platforms) {
    final next = List<PlatformModel>.unmodifiable(platforms ?? const []);
    final signature = next
        .map((item) => '${item.platform}|${item.prompt}|${item.link}')
        .join('\n');
    if (signature != _configurationSignature) {
      _configurationSignature = signature;
      alreadyChecked = false;
    }
    _platforms = next;
  }

  static Future<void> versionCheck(BuildContext context) async {
    if (alreadyChecked) return;
    // Deduplicate concurrent calls and let every caller observe completion.
    final pending = _pendingCheck;
    if (pending != null) {
      await pending;
      return;
    }
    _pendingCheck = _doVersionCheck(context);
    try {
      await _pendingCheck;
    } finally {
      _pendingCheck = null;
    }
  }

  static Future<void> _doVersionCheck(BuildContext context) async {
    final platform = _nativePlatformName();
    final target = resolveNativeTarget(_platforms, platform);
    if (target == null) {
      alreadyChecked = true;
      return;
    }

    final packageInfo = await PackageInfo.fromPlatform();
    if (!isVersionOutdated(packageInfo.version, target.prompt!)) {
      alreadyChecked = true;
      return;
    }
    if (!context.mounted) return;

    final updateConfirmed = await DialogHelper.showConfirmationDialog(
      context,
      CommonStrings.newVersionAvailable,
      CommonStrings.updateAppPrompt,
      confirmButtonMessage: CommonStrings.update,
    );
    alreadyChecked = true;
    if (updateConfirmed) {
      await LaunchUrlService.openExternalUrl(target.link!);
    }
  }

  static String? _nativePlatformName() {
    if (!PlatformHelper.isNative) return null;
    if (PlatformHelper.isIOS) return 'ios';
    if (PlatformHelper.isAndroid) return 'droid';
    return null;
  }

  @visibleForTesting
  static PlatformModel? resolveNativeTarget(
    List<PlatformModel> platforms,
    String? platform,
  ) {
    if (platform != 'ios' && platform != 'droid') return null;
    for (final candidate in platforms) {
      if (candidate.platform?.toLowerCase() == platform &&
          candidate.prompt?.trim().isNotEmpty == true &&
          candidate.link?.trim().isNotEmpty == true) {
        return candidate;
      }
    }
    return null;
  }

  @visibleForTesting
  static bool isVersionOutdated(
      String currentVersion, String recommendedVersion) {
    final current = _parseVersion(currentVersion);
    final recommended = _parseVersion(recommendedVersion);
    if (current == null || recommended == null) return false;

    final length = current.length > recommended.length
        ? current.length
        : recommended.length;
    for (var index = 0; index < length; index++) {
      final currentPart = index < current.length ? current[index] : 0;
      final recommendedPart =
          index < recommended.length ? recommended[index] : 0;
      if (currentPart < recommendedPart) {
        return true;
      } else if (currentPart > recommendedPart) {
        return false;
      }
    }
    return false;
  }

  static List<int>? _parseVersion(String value) {
    final normalized = value.split('+').first.trim();
    if (normalized.isEmpty) return null;
    final parts = <int>[];
    for (final rawPart in normalized.split('.')) {
      final part = int.tryParse(rawPart);
      if (part == null || part < 0) return null;
      parts.add(part);
    }
    return parts;
  }
}
