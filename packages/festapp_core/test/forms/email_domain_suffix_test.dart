import 'dart:convert';
import 'dart:io';
import 'package:festapp_core/forms.dart';
import 'package:test/test.dart';

void main() {
  final cases =
      jsonDecode(
            File(
              '../../shared/email/domain-suffix-cases.json',
            ).readAsStringSync(),
          )
          as List;
  for (final c in cases) {
    test(c['email'] as String, () {
      final result = EmailDomainSuffix.classify(c['email'] as String);
      expect(result.status.name, c['status']);
      expect(result.suffix, c['suffix']);
    });
  }
  test('every IANA suffix is recognized', () {
    final lines = File(
      '../../shared/email/iana-tlds.txt',
    ).readAsLinesSync().skip(1);
    for (final suffix in lines) {
      expect(
        EmailDomainSuffix.classify('local@example.$suffix').status,
        EmailDomainSuffixStatus.knownSuffix,
        reason: suffix,
      );
    }
  });
  test('confirmation is exact, local, and revoked by any edit', () {
    final first = EmailSuffixConfirmation()..update('A@example.czz');
    final second = EmailSuffixConfirmation()..update('A@example.czz');
    expect(first.needsConfirmation, isTrue);
    first.confirm();
    expect(first.needsConfirmation, isFalse);
    expect(second.needsConfirmation, isTrue);
    first.update('a@example.czz');
    expect(first.needsConfirmation, isTrue);
    first.update('');
    expect(first.needsConfirmation, isFalse);
  });
}
