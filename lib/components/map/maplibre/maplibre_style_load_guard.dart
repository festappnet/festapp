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
