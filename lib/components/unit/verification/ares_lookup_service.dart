import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

enum AresLookupFailure {
  invalidRegistrationNumber,
  notFound,
  unavailable,
  invalidResponse,
}

class AresLookupException implements Exception {
  const AresLookupException(this.failure);
  final AresLookupFailure failure;
}

/// Public registry facts for an editable draft, never a verification decision.
class AresCompany {
  const AresCompany({
    required this.legalName,
    required this.countryCode,
    required this.registrationNumber,
    this.vatId,
    required this.street,
    required this.city,
    required this.postalCode,
  });

  final String legalName, countryCode, registrationNumber;
  final String? vatId;
  final String street, city, postalCode;

  Map<String, dynamic> toProfileDraft() => {
        'legalName': legalName,
        'countryCode': countryCode,
        'registrationNumber': registrationNumber,
        'vatId': vatId ?? '',
        'address': {
          'street': street,
          'city': city,
          'postalCode': postalCode,
        },
      };
}

class AresLookupService {
  AresLookupService({http.Client? client}) : _client = client;
  final http.Client? _client;

  static String normalizeRegistrationNumber(String input) {
    final digits = input.replaceAll(RegExp(r'\s'), '');
    if (!RegExp(r'^\d{1,8}$').hasMatch(digits)) {
      throw const AresLookupException(
          AresLookupFailure.invalidRegistrationNumber);
    }
    final ico = digits.padLeft(8, '0');
    var sum = 0;
    for (var i = 0; i < 7; i++) {
      sum += int.parse(ico[i]) * (8 - i);
    }
    if (ico == '00000000' || (11 - sum % 11) % 10 != int.parse(ico[7])) {
      throw const AresLookupException(
          AresLookupFailure.invalidRegistrationNumber);
    }
    return ico;
  }

  Future<AresCompany> lookup(String input) async {
    final ico = normalizeRegistrationNumber(input);
    final uri = Uri.https('ares.gov.cz',
        '/ekonomicke-subjekty-v-be/rest/ekonomicke-subjekty/$ico');
    late http.Response response;
    try {
      response =
          await (_client?.get(uri, headers: {'Accept': 'application/json'}) ??
                  http.get(uri, headers: {'Accept': 'application/json'}))
              .timeout(const Duration(seconds: 10));
    } on TimeoutException {
      throw const AresLookupException(AresLookupFailure.unavailable);
    } on http.ClientException {
      throw const AresLookupException(AresLookupFailure.unavailable);
    }
    if (response.statusCode == 404) {
      throw const AresLookupException(AresLookupFailure.notFound);
    }
    if (response.statusCode != 200) {
      throw const AresLookupException(AresLookupFailure.unavailable);
    }
    try {
      final value = jsonDecode(utf8.decode(response.bodyBytes));
      if (value is! Map<String, dynamic> ||
          value['ico'] != ico ||
          value['obchodniJmeno'] is! String ||
          (value['obchodniJmeno'] as String).trim().isEmpty) {
        throw const FormatException('Missing registry identity');
      }
      final address = value['sidlo'];
      if (address != null && address is! Map<String, dynamic>) {
        throw const FormatException('Invalid registered address');
      }
      final fields = address as Map<String, dynamic>? ?? {};
      String text(dynamic item) => item is String ? item.trim() : '';
      String number(dynamic item) =>
          item is int && item > 0 ? '$item' : text(item);
      final house = number(fields['cisloDomovni']);
      final orientation = number(fields['cisloOrientacni']);
      final suffix = text(fields['cisloOrientacniPismeno']);
      final streetName = text(fields['nazevUlice']);
      final locality = text(fields['nazevCastiObce']);
      final houseLabel = house.isEmpty
          ? '$orientation$suffix'
          : orientation.isEmpty
              ? house
              : '$house/$orientation$suffix';
      final street = [streetName.isEmpty ? locality : streetName, houseLabel]
          .where((part) => part.isNotEmpty)
          .join(' ');
      final country = text(fields['kodStatu']);
      return AresCompany(
        legalName: text(value['obchodniJmeno']),
        registrationNumber: ico,
        countryCode: country.isEmpty ? 'CZ' : country,
        vatId: text(value['dic']).isEmpty ? null : text(value['dic']),
        street: street,
        city: text(fields['nazevObce']),
        postalCode: number(fields['psc']),
      );
    } on FormatException {
      throw const AresLookupException(AresLookupFailure.invalidResponse);
    }
  }
}
