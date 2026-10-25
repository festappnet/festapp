import 'package:material_ui/material_ui.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:fstapp/components/offline/offline_strings.dart';
import 'package:fstapp/data_services/offline_data_service.dart';
import 'package:fstapp/services/connectivity_service.dart';
import 'package:fstapp/services/time_helper.dart';
import 'package:fstapp/theme_config.dart';

/// Thin single-line strip above the occasion shell content while offline:
/// a cloud-off icon, a slightly emphasised "Offline", and the last sync time
/// when one is stored. Online it renders nothing. Pages outside the occasion
/// shell (login, unit) knowingly have none.
class OfflineBanner extends StatelessWidget {
  final Future<DateTime?> Function() loadLastSyncedAt;

  const OfflineBanner(
      {super.key, Future<DateTime?> Function()? loadLastSyncedAt})
      : loadLastSyncedAt =
            loadLastSyncedAt ?? OfflineDataService.getLastSyncedAt;

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<bool>(
      valueListenable: ConnectivityService.isOfflineNotifier,
      builder: (context, isOffline, _) {
        if (!isOffline) return const SizedBox.shrink();
        return Material(
          color: ThemeConfig.grey300(context),
          child: FutureBuilder<DateTime?>(
            future: loadLastSyncedAt(),
            builder: (context, snapshot) {
              final last = snapshot.data;
              return Padding(
                padding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
                child: Row(
                  children: [
                    Icon(Icons.cloud_off,
                        size: 17, color: ThemeConfig.grey700(context)),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text.rich(
                        TextSpan(children: [
                          // "Offline" is the emphasised bit — but gently:
                          // semibold, a muted-dark grey, not full black.
                          TextSpan(
                            text: OfflineStrings.offline,
                            style: TextStyle(
                              color: ThemeConfig.grey800(context),
                              fontWeight: FontWeight.w600,
                              fontSize: 12.5,
                            ),
                          ),
                          // The last-sync time stays muted and secondary, as a
                          // humanized "… ago" rather than a raw date.
                          if (last != null)
                            TextSpan(
                              text:
                                  "  ·  ${OfflineStrings.updatedAt(TimeHelper.timeAgo(last, context.locale.languageCode))}",
                              style: TextStyle(
                                color: ThemeConfig.grey600(context),
                                fontSize: 12.5,
                              ),
                            ),
                        ]),
                        maxLines: 1,
                        softWrap: false,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),
              );
            },
          ),
        );
      },
    );
  }
}
