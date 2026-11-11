/// The capability stays in this one internal destination during sign-in.
/// It is never a general redirect URL or a directory/account lookup key.
abstract final class AccessInvitationDestination {
  static const route = 'team-invitation';

  static String? token(String? value) {
    final uri = value == null ? null : Uri.tryParse(value);
    if (uri == null ||
        uri.hasScheme ||
        uri.hasAuthority ||
        uri.hasFragment ||
        uri.path != '/$route' ||
        uri.queryParametersAll.length != 1) {
      return null;
    }
    final values = uri.queryParametersAll['token'];
    if (values == null ||
        values.length != 1 ||
        !RegExp(r'^[0-9a-f]{64}$').hasMatch(values.single))
      return null;
    return values.single;
  }

  static String location(String value) {
    if (!RegExp(r'^[0-9a-f]{64}$').hasMatch(value)) {
      throw ArgumentError('Invalid invitation token');
    }
    return Uri(path: '/$route', queryParameters: {'token': value}).toString();
  }
}
