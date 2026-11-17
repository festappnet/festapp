enum MeasurementRequestState {
  unavailable,
  notRequested,
  requested,
  retryAvailable,
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
        requestState: switch (json['request_state']) {
          'not_requested' => MeasurementRequestState.notRequested,
          'requested' => MeasurementRequestState.requested,
          'retry_available' => MeasurementRequestState.retryAvailable,
          _ => MeasurementRequestState.unavailable,
        },
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
