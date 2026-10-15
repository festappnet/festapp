import 'package:flutter_test/flutter_test.dart';
import 'package:fstapp/components/schedule/schedule_page.dart';

void main() {
  test('disabled companions do not call the optional backend', () async {
    var calls = 0;

    final result = await loadOptionalCompanionOwnership(
      isLoggedIn: true,
      featureEnabled: false,
      loadCompanions: () async {
        calls++;
        return const [];
      },
    );

    expect(result, isFalse);
    expect(calls, 0);
  });

  test('optional companion failure cannot block program loading', () async {
    Object? reportedError;

    final result = await loadOptionalCompanionOwnership(
      isLoggedIn: true,
      featureEnabled: true,
      loadCompanions: () => Future.error(StateError('RPC unavailable')),
      onError: (error) => reportedError = error,
    );

    expect(result, isFalse);
    expect(reportedError, isA<StateError>());
  });
}
