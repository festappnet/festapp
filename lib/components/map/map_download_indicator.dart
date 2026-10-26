import 'package:material_ui/material_ui.dart';

sealed class MapDownloadState {
  const MapDownloadState();

  bool get isBusy => this is MapDownloadCheckingCache || this is MapDownloading;
}

final class MapDownloadIdle extends MapDownloadState {
  const MapDownloadIdle();
}

final class MapDownloadCheckingCache extends MapDownloadState {
  const MapDownloadCheckingCache();
}

final class MapDownloading extends MapDownloadState {
  final double progress;

  const MapDownloading(double progress)
      : progress = progress < 0
            ? 0
            : progress > 1
                ? 1
                : progress;
}

final class MapDownloadCompleted extends MapDownloadState {
  const MapDownloadCompleted();
}

/// The single visual owner of map download progress.
///
/// Cache checks intentionally render nothing. Actual downloads always expose a
/// determinate progress value, so an indeterminate spinner cannot overlap the
/// percentage indicator.
final class MapDownloadIndicator extends StatelessWidget {
  final MapDownloadState state;
  final bool useOffline;

  const MapDownloadIndicator({
    required this.state,
    required this.useOffline,
    super.key,
  });

  @override
  Widget build(BuildContext context) {
    if (state case MapDownloadIdle() || MapDownloadCheckingCache()) {
      return const SizedBox.shrink();
    }

    final alignment = useOffline ? Alignment.center : Alignment.topRight;
    final padding = useOffline
        ? EdgeInsets.zero
        : const EdgeInsets.only(top: 16, right: 16);
    return IgnorePointer(
      child: Align(
        alignment: alignment,
        child: Padding(
          padding: padding,
          child: Container(
            width: 40,
            height: 40,
            decoration: const BoxDecoration(
              color: Colors.black45,
              shape: BoxShape.circle,
            ),
            child: switch (state) {
              MapDownloading(:final progress) => Stack(
                  alignment: Alignment.center,
                  children: [
                    SizedBox(
                      width: 40,
                      height: 40,
                      child: CircularProgressIndicator(
                        strokeWidth: 3,
                        value: progress,
                        valueColor: const AlwaysStoppedAnimation<Color>(
                          Colors.white,
                        ),
                      ),
                    ),
                    Text(
                      '${(progress * 100).toInt()}%',
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 10,
                      ),
                    ),
                  ],
                ),
              MapDownloadCompleted() =>
                const Icon(Icons.check, size: 18, color: Colors.white),
              MapDownloadIdle() ||
              MapDownloadCheckingCache() =>
                const SizedBox.shrink(),
            },
          ),
        ),
      ),
    );
  }
}
