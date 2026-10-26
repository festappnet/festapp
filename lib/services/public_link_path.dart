/// Replace exactly one resolved slug, retaining subpage, query and capability.
String canonicalPublicPath(
    String path, String kind, String requested, String canonical) {
  if (requested.isEmpty || canonical.isEmpty || requested == canonical)
    return path;
  final end = path.indexOf(RegExp(r'[?#]'));
  final pathname = end < 0 ? path : path.substring(0, end);
  if (!pathname.startsWith('/') || pathname.startsWith('//')) return path;
  final parts = pathname.split('/');
  final index =
      kind == 'form' ? (parts.length > 2 && parts[1] == 'form' ? 2 : -1) : 1;
  if (index < 0 || index >= parts.length) return path;
  try {
    if (Uri.decodeComponent(parts[index]) != requested) return path;
  } on FormatException {
    return path;
  }
  parts[index] = Uri.encodeComponent(canonical);
  return parts.join('/') + (end < 0 ? '' : path.substring(end));
}
