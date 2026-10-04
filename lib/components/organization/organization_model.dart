class PlatformModel {
  String? link;
  String? prompt;
  String? platform;

  PlatformModel({
    this.link,
    this.prompt,
    this.platform,
  });

  factory PlatformModel.fromJson(Map<String, dynamic> json) => PlatformModel(
        link: json['link'] as String?,
        prompt: json['prompt'] as String?,
        platform: json['platform'] as String?,
      );

  Map<String, dynamic> toJson() {
    final Map<String, dynamic> data = {};
    if (link != null && link!.isNotEmpty) data['link'] = link;
    if (prompt != null && prompt!.isNotEmpty) data['prompt'] = prompt;
    if (platform != null && platform!.isNotEmpty) data['platform'] = platform;
    return data;
  }
}

class OrganizationModel {
  String? title;
  String? appName;
  List<PlatformModel>? platforms;
  String? defaultUrl;
  String? defaultLanguage;
  String? oneSignalAppId;
  bool? isRegistrationEnabled;
  bool? isGoogleLoginEnabled;
  bool?
      isUnitCreationEnabled; // Not in user JSON request but kept as it was there
  bool? isAppSupported;
  int? defaultUnit;
  int? representativeOccasion;
  List<String>? phonePrefixes;

  OrganizationModel({
    this.title,
    this.appName,
    this.platforms,
    this.defaultUrl,
    this.defaultLanguage,
    this.oneSignalAppId,
    this.isRegistrationEnabled,
    this.isGoogleLoginEnabled,
    this.isUnitCreationEnabled,
    this.isAppSupported,
    this.defaultUnit,
    this.representativeOccasion,
    this.phonePrefixes,
  });

  factory OrganizationModel.fromJson(Map<String, dynamic> json) {
    return OrganizationModel(
      title: json['title'] as String?,
      appName: json['APP_NAME'] as String?,
      platforms: json['PLATFORMS'] is List
          ? List<PlatformModel>.from((json['PLATFORMS'] as List)
              .map((x) => PlatformModel.fromJson(x as Map<String, dynamic>)))
          : [],
      defaultUrl: json['DEFAULT_URL'] as String?,
      defaultLanguage: json['DEFAULT_LANGUAGE'] as String?,
      oneSignalAppId: json['ONESIGNAL_APP_ID'] as String?,
      isRegistrationEnabled: json['IS_REGISTRATION_ENABLED'] as bool?,
      isGoogleLoginEnabled: json['IS_GOOGLE_LOGIN_ENABLED'] as bool?,
      isUnitCreationEnabled: json['IS_UNIT_CREATION_ENABLED'] as bool?,
      isAppSupported: json['IS_APP_SUPPORTED'] as bool?,
      defaultUnit: json['DEFAULT_UNIT'] as int?,
      representativeOccasion: json['REPRESENTATIVE_OCCASION'] as int?,
      phonePrefixes: json['PHONE_PREFIXES'] != null
          ? List<String>.from(json['PHONE_PREFIXES'])
          : null,
    );
  }

  Map<String, dynamic> toJson() {
    final Map<String, dynamic> data = {};

    // Helper to only add non-null and non-empty values
    void addIfNotEmpty(String key, dynamic value) {
      if (value == null) return;
      if (value is String && value.isEmpty) return;
      if (value is List && value.isEmpty) return;
      data[key] = value;
    }

    addIfNotEmpty('title', title);
    addIfNotEmpty('APP_NAME', appName);

    if (platforms != null && platforms!.isNotEmpty) {
      data['PLATFORMS'] = platforms!.map((p) => p.toJson()).toList();
    }

    addIfNotEmpty('DEFAULT_URL', defaultUrl);
    addIfNotEmpty('DEFAULT_LANGUAGE', defaultLanguage);
    addIfNotEmpty('ONESIGNAL_APP_ID', oneSignalAppId);
    addIfNotEmpty('IS_REGISTRATION_ENABLED', isRegistrationEnabled);
    addIfNotEmpty('IS_GOOGLE_LOGIN_ENABLED', isGoogleLoginEnabled);
    addIfNotEmpty('IS_UNIT_CREATION_ENABLED', isUnitCreationEnabled);
    addIfNotEmpty('IS_APP_SUPPORTED', isAppSupported);
    addIfNotEmpty('DEFAULT_UNIT', defaultUnit);
    addIfNotEmpty('REPRESENTATIVE_OCCASION', representativeOccasion);
    if (phonePrefixes != null && phonePrefixes!.isNotEmpty) {
      data['PHONE_PREFIXES'] = phonePrefixes;
    }

    return data;
  }
}
