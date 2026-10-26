bool canShowCompanionAttendanceAction({
  required bool isLoggedIn,
  required bool eventSupportsSignIn,
  required bool featureEnabled,
  required bool hasOwnedCompanions,
}) =>
    isLoggedIn && eventSupportsSignIn && featureEnabled && hasOwnedCompanions;

bool canShowCompanionManagement({
  required bool featureEnabled,
  required bool allowUserCreate,
  required bool hasOwnedCompanions,
}) =>
    featureEnabled && (allowUserCreate || hasOwnedCompanions);

bool canShowCompanionQrAction({required bool entryCodeEnabled}) =>
    entryCodeEnabled;
