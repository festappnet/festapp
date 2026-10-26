/// Trimmed customer name, then email. Identifiers are never contact labels.
String formatCustomerLabel({String? name, String? surname, String? email}) {
  final parts = [name, surname]
      .whereType<String>()
      .map((part) => part.trim())
      .where((part) => part.isNotEmpty);
  final label = parts.join(' ');
  return label.isNotEmpty ? label : (email?.trim() ?? '');
}
