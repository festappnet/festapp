class LoginQrPayload {
  const LoginQrPayload._({required this.raw, required this.occasion});

  final String raw;
  final int occasion;

  static final RegExp _pattern = RegExp(
    r'^festapp-login:v1:([1-9][0-9]*):[A-Za-z0-9_-]{40,80}$',
  );

  static LoginQrPayload? tryParse(String? raw) {
    if (raw == null) return null;
    final normalized = raw.trim();
    if (normalized.length > 160) return null;
    final match = _pattern.firstMatch(normalized);
    if (match == null) return null;
    final occasion = int.tryParse(match.group(1)!);
    if (occasion == null) return null;
    return LoginQrPayload._(raw: normalized, occasion: occasion);
  }

  static LoginQrPayload? firstValid(Iterable<String?> values) {
    for (final value in values) {
      final parsed = tryParse(value);
      if (parsed != null) return parsed;
    }
    return null;
  }
}
