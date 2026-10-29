import 'package:festapp_core/forms.dart';
import 'package:test/test.dart';

void main() {
  test(
    'authoring validation preserves the absent server default and explicit policies',
    () {
      for (final policy in [
        null,
        {},
        {'type': 'random'},
        {'type': 'sequence', 'starting_number': 1},
        {'type': 'sequence', 'starting_number': 9999999999},
      ]) {
        expect(formVariableSymbolPolicyValid(policy), true, reason: '$policy');
      }
      for (final policy in [
        false,
        {'type': 'unknown'},
        {'type': 'sequence'},
        {'type': 'sequence', 'starting_number': null},
        {'type': 'sequence', 'starting_number': 0},
        {'type': 'sequence', 'starting_number': 10000000000},
        {'type': 'sequence', 'starting_number': 1.5},
        {'type': 'sequence', 'starting_number': '12'},
      ]) {
        expect(formVariableSymbolPolicyValid(policy), false, reason: '$policy');
      }
    },
  );
}
