/// Authorized public read projection. Never included in form writes.
class VerifiedOrganizationIdentity {
  final int unitId, revision;
  final String legalName,
      countryCode,
      registrationNumber,
      street,
      city,
      postalCode,
      contactEmail;
  final String? vatId, phone, website, verifiedAt;
  const VerifiedOrganizationIdentity._(
      this.unitId,
      this.revision,
      this.legalName,
      this.countryCode,
      this.registrationNumber,
      this.street,
      this.city,
      this.postalCode,
      this.contactEmail,
      this.vatId,
      this.phone,
      this.website,
      this.verifiedAt);
  static VerifiedOrganizationIdentity? tryParse(dynamic value) {
    if (value is! Map || value['address'] is! Map) return null;
    final address = value['address'] as Map;
    bool text(dynamic v) => v is String && v.trim().isNotEmpty;
    if (value['unitId'] is! int ||
        value['unitId'] <= 0 ||
        value['revision'] is! int ||
        value['revision'] <= 0 ||
        !['legalName', 'countryCode', 'registrationNumber', 'contactEmail']
            .every((k) => text(value[k])) ||
        !['street', 'city', 'postalCode'].every((k) => text(address[k])) ||
        !RegExp(r'^[A-Z]{2}$').hasMatch(value['countryCode']) ||
        ['vatId', 'phone', 'website']
            .any((k) => value[k] != null && value[k] is! String)) return null;
    final verifiedAt = value['verifiedAt'];
    if (verifiedAt != null &&
        (verifiedAt is! String || DateTime.tryParse(verifiedAt) == null)) {
      return null;
    }
    return VerifiedOrganizationIdentity._(
        value['unitId'],
        value['revision'],
        value['legalName'],
        value['countryCode'],
        value['registrationNumber'],
        address['street'],
        address['city'],
        address['postalCode'],
        value['contactEmail'],
        value['vatId'],
        value['phone'],
        value['website'],
        verifiedAt);
  }

  Map<String, dynamic> get details => {
        'legalName': legalName,
        'countryCode': countryCode,
        'registrationNumber': registrationNumber,
        'vatId': vatId,
        'address': {'street': street, 'city': city, 'postalCode': postalCode},
        'contactEmail': contactEmail,
        'phone': phone,
        'website': website
      };
}
