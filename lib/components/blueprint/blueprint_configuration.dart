class BlueprintConfiguration {
  static const String metaDimensions = "dimensions";
  static const String metaWidth = "width";
  static const String metaHeight = "height";

  int? width;
  int? height;

  factory BlueprintConfiguration.fromJson(Map<String, dynamic> json) {
    final dimensions = json[metaDimensions] as Map<String, dynamic>?;
    return BlueprintConfiguration(
      width: dimensions?[metaWidth],
      height: dimensions?[metaHeight],
    );
  }

  Map<String, dynamic> toJson() => {
        metaDimensions: {
          metaWidth: width,
          metaHeight: height,
        },
      };

  BlueprintConfiguration({
    this.width,
    this.height,
  });
}
