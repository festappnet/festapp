class UnitWebsiteConsentBinding {
  final String id;
  final String websiteOrigin;
  final String platform;
  final int version;
  final String state;
  final Map<String, dynamic> providerConfig;

  UnitWebsiteConsentBinding.fromJson(Map<String, dynamic> json)
    : id = json['id'] as String,
      websiteOrigin = json['websiteOrigin'] as String,
      platform = json['platform'] as String,
      version = json['version'] as int,
      state = json['state'] as String,
      providerConfig = Map<String, dynamic>.from(json['providerConfig'] as Map);
}

class UnitWebsiteConsent {
  final String consentRevision;
  final List<UnitWebsiteConsentBinding> bindings;

  UnitWebsiteConsent.fromJson(Map<String, dynamic> json)
    : consentRevision = json['consentRevision'] as String,
      bindings = (json['bindings'] as List)
          .map(
            (v) => UnitWebsiteConsentBinding.fromJson(
              Map<String, dynamic>.from(v as Map),
            ),
          )
          .toList();

  UnitWebsiteConsentBinding? forWebsite(String origin) {
    for (final binding in bindings) {
      if (binding.websiteOrigin == origin) return binding;
    }
    return null;
  }
}

/// A fresh server probe rejected the reviewed ID before any binding was saved.
class ComplianzPolicyChanged implements Exception {
  const ComplianzPolicyChanged();
}
