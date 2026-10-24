/// Practical mailbox syntax for customer contact addresses. No DNS or delivery check.
class EmailAddress {
  static final _local = RegExp(r"^[a-zA-Z0-9.!#$%&'*+/=?^_`{|}~-]+$");
  static final _label = RegExp(r'^[a-zA-Z0-9](?:[a-zA-Z0-9-]{0,61}[a-zA-Z0-9])?$');

  static bool isValid(String? value) {
    if (value == null || value.length > 254 || RegExp(r'\s').hasMatch(value)) return false;
    final parts = value.split('@');
    if (parts.length != 2) return false;
    final local = parts[0];
    final domain = parts[1].split('.');
    return local.isNotEmpty && local.length <= 64 &&
        _local.hasMatch(local) && !local.startsWith('.') &&
        !local.endsWith('.') && !local.contains('..') &&
        domain.length >= 2 && domain.every((label) =>
            label.isNotEmpty && _label.hasMatch(label) &&
            !label.contains('\n') && !label.contains('\r')) &&
        !RegExp(r'^[0-9]+$').hasMatch(domain.last);
  }
}
