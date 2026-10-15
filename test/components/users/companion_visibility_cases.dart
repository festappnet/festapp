import 'package:flutter_test/flutter_test.dart';
import 'package:fstapp/components/users/companion/companion_visibility.dart';

void main() {
  test('attendance action requires an owned companion and the master gate', () {
    expect(
      canShowCompanionAttendanceAction(
        isLoggedIn: true,
        eventSupportsSignIn: true,
        featureEnabled: true,
        hasOwnedCompanions: false,
      ),
      isFalse,
    );
    expect(
      canShowCompanionAttendanceAction(
        isLoggedIn: true,
        eventSupportsSignIn: true,
        featureEnabled: true,
        hasOwnedCompanions: true,
      ),
      isTrue,
    );
    expect(
      canShowCompanionAttendanceAction(
        isLoggedIn: true,
        eventSupportsSignIn: true,
        featureEnabled: false,
        hasOwnedCompanions: true,
      ),
      isFalse,
    );
  });

  test('profile management is visible for creation or existing ownership', () {
    expect(
      canShowCompanionManagement(
        featureEnabled: true,
        allowUserCreate: true,
        hasOwnedCompanions: false,
      ),
      isTrue,
    );
    expect(
      canShowCompanionManagement(
        featureEnabled: true,
        allowUserCreate: false,
        hasOwnedCompanions: false,
      ),
      isFalse,
    );
    expect(
      canShowCompanionManagement(
        featureEnabled: true,
        allowUserCreate: false,
        hasOwnedCompanions: true,
      ),
      isTrue,
    );
  });

  test('companion QR action follows the entry-code feature gate', () {
    expect(canShowCompanionQrAction(entryCodeEnabled: false), isFalse);
    expect(canShowCompanionQrAction(entryCodeEnabled: true), isTrue);
  });
}
