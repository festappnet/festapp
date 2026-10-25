/// The largest file, in bytes, whose content is preloaded into memory when
/// `FilePickerWebOptions.withData` is `true`.
///
/// Browsers cannot reliably hold a single buffer above 2 GB: Chrome fails the
/// read (and can crash the tab when a debugger is attached) and Firefox
/// rejects buffers that large. Larger files are still read on demand through
/// `PlatformFile.readAsBytes()` and `readAsByteStream()`.
const int maxPreloadBytes = 2 * 1024 * 1024 * 1024;

/// Whether a picked file of [size] bytes should be read into memory at pick
/// time.
bool shouldPreloadBytes(int size, {required bool withData}) =>
    withData && size <= maxPreloadBytes;
