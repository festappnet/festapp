import 'pwa_storage_port.dart';

PwaStoragePort createPwaStoragePort() => const UnsupportedPwaStoragePort();

class UnsupportedPwaStoragePort implements PwaStoragePort {
  const UnsupportedPwaStoragePort();

  @override
  Future<PwaStorageReport> inspect() async => const PwaStorageReport(
        estimate: PwaStorageEstimate(),
        shells: PwaShellReport(blocker: 'unsupported-browser'),
      );

  @override
  Future<PwaShellReport> pruneUnusedShells() async =>
      const PwaShellReport(blocker: 'unsupported-browser');
}
