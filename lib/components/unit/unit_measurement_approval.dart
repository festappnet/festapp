enum MeasurementRequestState {
  unavailable,
  notRequested,
  requested,
  retryAvailable;

  static MeasurementRequestState fromJson(Object? value) => switch (value) {
    'not_requested' => notRequested,
    'requested' => requested,
    'retry_available' => retryAvailable,
    _ => unavailable,
  };
}

class UnitMeasurementApproval {
  final MeasurementRequestState requestState;
  final bool canRequest;
  final List<String> savedOrigins;
  final bool approved;
  final bool organizationAllowed;
  final bool runtimeSupported;
  final DateTime? requestedAt;

  const UnitMeasurementApproval({
    this.requestState = MeasurementRequestState.unavailable,
    this.canRequest = false,
    this.savedOrigins = const [],
    required this.approved,
    required this.organizationAllowed,
    required this.runtimeSupported,
    this.requestedAt,
  });

  factory UnitMeasurementApproval.fromJson(Map<String, dynamic> json) =>
      UnitMeasurementApproval(
        requestState: MeasurementRequestState.fromJson(json['request_state']),
        canRequest:
            json['can_request'] == true &&
            [
              'not_requested',
              'requested',
              'retry_available',
            ].contains(json['request_state']),
        savedOrigins: List<String>.from(json['saved_origins'] ?? const []),
        approved: json['approved'] == true,
        organizationAllowed: json['organization_allowed'] == true,
        runtimeSupported: json['runtime_supported'] == true,
        requestedAt: json['requested_at'] == null
            ? null
            : DateTime.parse(json['requested_at'] as String),
      );
}
