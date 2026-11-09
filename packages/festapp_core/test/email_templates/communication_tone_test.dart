import 'dart:convert';
import 'dart:io';
import 'package:festapp_core/communication_tone.dart';
import 'package:test/test.dart';

void main() {
  test('communication tone follows the shared inheritance contract', () {
    final cases =
        jsonDecode(
              File(
                '../festapp_contracts/communication-tone-cases.json',
              ).readAsStringSync(),
            )
            as List;
    final contract =
        jsonDecode(
              File(
                '../festapp_contracts/communication-tone.json',
              ).readAsStringSync(),
            )
            as Map;
    expect(
      CommunicationTone.values,
      unorderedEquals(contract['values'] as List),
    );
    for (final c in cases) {
      expect(
        CommunicationTone.resolve(c['value'], c['inherited']),
        c['expected'],
      );
    }
    for (final value in [
      true,
      42,
      {},
      [],
      ['informal'],
    ]) {
      expect(CommunicationTone.parse(value), isNull);
      expect(CommunicationTone.resolve(value, 'informal'), 'informal');
    }
  });
}
