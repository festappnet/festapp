class PwaStorageEstimate {
  const PwaStorageEstimate(
      {this.usageBytes, this.quotaBytes, this.usageDetails = const {}});

  final int? usageBytes;
  final int? quotaBytes;
  final Map<String, int> usageDetails;
}

class PwaShellReport {
  const PwaShellReport({
    this.current,
    this.live = const [],
    this.unknownClients = 0,
    this.retained = const [],
    this.deletable = const [],
    this.deleted = const [],
    this.blocker,
  });

  final String? current;
  final List<String> live;
  final int unknownClients;
  final List<String> retained;
  final List<String> deletable;
  final List<String> deleted;
  final String? blocker;
}

class PwaStorageReport {
  const PwaStorageReport({required this.estimate, required this.shells});

  final PwaStorageEstimate estimate;
  final PwaShellReport shells;
}

abstract class PwaStoragePort {
  Future<PwaStorageReport> inspect();
  Future<PwaShellReport> pruneUnusedShells();
}
