/// Early authoring validation only. SQL owns normalization and VS allocation.
/// Absent/null policy keeps the existing server default (random).
bool formVariableSymbolPolicyValid(Object? policy) {
  if (policy == null) return true;
  if (policy is! Map) return false;
  final type = policy['type'];
  if (type != null && type != 'random' && type != 'sequence') return false;
  final number = policy['starting_number'];
  if (number == null) return type != 'sequence';
  return number is int && number >= 1 && number <= 9999999999;
}
