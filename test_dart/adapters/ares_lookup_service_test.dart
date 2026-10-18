import 'dart:async';
import 'dart:convert';

import 'package:fstapp/components/unit/verification/ares_lookup_service.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:test/test.dart';

final ministry = {
  'ico': '00006947',
  'obchodniJmeno': 'Ministerstvo financí',
  'dic': 'CZ00006947',
  'sidlo': {
    'kodStatu': 'CZ',
    'nazevUlice': 'Letenská',
    'cisloDomovni': 525,
    'cisloOrientacni': 15,
    'nazevObce': 'Praha',
    'psc': 11800,
  },
  'contactEmail': 'must-not-import@example.test',
  'status': 'verified',
};
Matcher fails(AresLookupFailure failure) => throwsA(isA<AresLookupException>()
    .having((error) => error.failure, 'failure', failure));

void main() {
  test('queries official ARES with normalized ICO and maps only legal facts',
      () async {
    final service = AresLookupService(client: MockClient((request) async {
      expect(request.url.toString(),
          'https://ares.gov.cz/ekonomicke-subjekty-v-be/rest/ekonomicke-subjekty/00006947');
      expect(request.headers.containsKey('authorization'), isFalse);
      return http.Response.bytes(utf8.encode(jsonEncode(ministry)), 200);
    }));
    final result = await service.lookup('6 947');
    expect(result.toProfileDraft(), {
      'legalName': 'Ministerstvo financí',
      'countryCode': 'CZ',
      'registrationNumber': '00006947',
      'vatId': 'CZ00006947',
      'address': {
        'street': 'Letenská 525/15',
        'city': 'Praha',
        'postalCode': '11800'
      },
    });
  });

  test('rejects malformed and bad-checksum ICO without a network request',
      () async {
    var requests = 0;
    final service = AresLookupService(client: MockClient((_) async {
      requests++;
      return http.Response('{}', 200);
    }));
    for (final input in [
      '',
      '00000000',
      '27074359',
      '123456789',
      '../00006947'
    ]) {
      await expectLater(service.lookup(input),
          fails(AresLookupFailure.invalidRegistrationNumber));
    }
    expect(requests, 0);
  });

  test(
      'supports rural addresses and orientation suffixes without inventing contacts',
      () async {
    final data = {
      ...ministry,
      'sidlo': {
        'kodStatu': 'CZ',
        'nazevCastiObce': 'Nová Ves',
        'cisloDomovni': 7,
        'cisloOrientacni': 2,
        'cisloOrientacniPismeno': 'a',
        'nazevObce': 'Nová Ves',
        'psc': 12345,
      }
    };
    final service = AresLookupService(
        client: MockClient((_) async =>
            http.Response.bytes(utf8.encode(jsonEncode(data)), 200)));
    final result = await service.lookup('00006947');
    expect(result.street, 'Nová Ves 7/2a');
    expect(result.toProfileDraft().containsKey('contactEmail'), isFalse);
    expect(result.toProfileDraft().containsKey('status'), isFalse);
  });

  test('missing address remains empty for manual completion', () async {
    final service = AresLookupService(
        client: MockClient((_) async => http.Response(
            jsonEncode({'ico': '00006947', 'obchodniJmeno': 'Registry entry'}),
            200)));
    final result = await service.lookup('00006947');
    expect(result.street, isEmpty);
    expect(result.city, isEmpty);
    expect(result.postalCode, isEmpty);
    expect(result.vatId, isNull);
  });

  for (final entry in {
    404: AresLookupFailure.notFound,
    429: AresLookupFailure.unavailable,
    503: AresLookupFailure.unavailable
  }.entries) {
    test('reports HTTP ${entry.key} as ${entry.value}', () async {
      final service = AresLookupService(
          client: MockClient((_) async => http.Response('{}', entry.key)));
      await expectLater(service.lookup('00006947'), fails(entry.value));
    });
  }

  test('rejects mismatched identities and malformed successful replies',
      () async {
    for (final body in [
      'not JSON',
      '[]',
      jsonEncode({...ministry, 'ico': '27074358'}),
      jsonEncode({...ministry, 'sidlo': []})
    ]) {
      final service = AresLookupService(
          client: MockClient((_) async => http.Response(body, 200)));
      await expectLater(
          service.lookup('00006947'), fails(AresLookupFailure.invalidResponse));
    }
  });

  test('network failures remain recoverable without retrying automatically',
      () async {
    var requests = 0;
    final service = AresLookupService(client: MockClient((_) async {
      requests++;
      throw http.ClientException('offline');
    }));
    await expectLater(
        service.lookup('00006947'), fails(AresLookupFailure.unavailable));
    expect(requests, 1);
  });

  test('bounds a stalled ARES request', () async {
    final service = AresLookupService(
        client: MockClient((_) => Completer<http.Response>().future));
    await expectLater(
        service.lookup('00006947'), fails(AresLookupFailure.unavailable));
  }, timeout: const Timeout(Duration(seconds: 15)));
}
