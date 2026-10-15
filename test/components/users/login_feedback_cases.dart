import 'package:flutter_test/flutter_test.dart';
import 'package:fstapp/components/users/login_feedback.dart';

void main() {
  test('shows sign-in feedback after post-login navigation', () async {
    final events = <String>[];

    await finishSuccessfulSignIn(
      navigate: () async => events.add('navigated'),
      showFeedback: () async => events.add('feedback'),
    );

    expect(events, ['navigated', 'feedback']);
  });

  test('keeps an authenticated login successful when navigation recovery runs',
      () async {
    final events = <String>[];

    await finishSuccessfulSignIn(
      navigate: () async => throw Exception('sync unavailable'),
      recoverNavigation: () async => events.add('recovered'),
      showFeedback: () async => events.add('feedback'),
    );

    expect(events, ['recovered', 'feedback']);
  });

  test('does not rotate a refresh token when a live session already exists',
      () async {
    var restoreCalls = 0;

    final authenticated = await ensureAuthenticatedSession(
      isLoggedIn: () => true,
      restoreSession: () async {
        restoreCalls++;
        return true;
      },
    );

    expect(authenticated, isTrue);
    expect(restoreCalls, 0);
  });
}
