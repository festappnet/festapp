import 'dart:async';

const mapLibreStyleLoadTimeout = Duration(seconds: 15);

/// Prevents a lost native style callback from leaving the map permanently
/// hidden behind its loading overlay.
class MapLibreStyleLoadWatchdog {
  MapLibreStyleLoadWatchdog({this.timeout = mapLibreStyleLoadTimeout});

  final Duration timeout;
  Timer? _timer;

  void arm({
    required void Function() revealBaseMap,
    required void Function() onTimeout,
  }) {
    cancel();
    _timer = Timer(timeout, () {
      _timer = null;
      onTimeout();
      revealBaseMap();
    });
  }

  void cancel() {
    _timer?.cancel();
    _timer = null;
  }

  void dispose() => cancel();
}

/// Starts optional native setup without making style readiness depend on a
/// permission dialog or another platform future that the user may leave open.
void startOptionalMapLibreSetup({
  required Future<void> Function() setup,
  required void Function(Object error, StackTrace stackTrace) onError,
}) {
  unawaited(
    Future<void>.sync(setup).catchError((Object error, StackTrace stackTrace) {
      onError(error, stackTrace);
    }),
  );
}

/// Keeps the native renderer synchronized when an installed offline bundle is
/// replaced while the Flutter map surface itself remains mounted.
bool reloadMapLibreStyleIfChanged({
  required String previousStyle,
  required String nextStyle,
  required void Function(String style) reload,
}) {
  if (previousStyle == nextStyle) return false;
  reload(nextStyle);
  return true;
}

/// Keeps the usable base map independent from optional scene decoration.
Future<void> completeMapLibreStyleLoad({
  required void Function() revealBaseMap,
  required Future<void> Function() decorateStyle,
  required void Function(Object error, StackTrace stackTrace) onDecorationError,
  required void Function() markCameraReady,
}) async {
  revealBaseMap();
  try {
    await decorateStyle();
  } catch (error, stackTrace) {
    onDecorationError(error, stackTrace);
  } finally {
    markCameraReady();
  }
}
