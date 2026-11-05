Future<String> verifySaleOpeningVisitor(
  String siteKey,
  String formLink,
  String email,
) => Future.error(StateError('verification_unavailable'));
