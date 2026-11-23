/// Native Wallet fields derived from the saved ticket appearance.
class GoogleWalletAppearance {
  const GoogleWalletAppearance({
    this.backgroundColor,
    this.logo,
    this.heroImage,
    this.galleryArtwork,
    this.logoOverridden = false,
  });
  final String? backgroundColor, logo, heroImage;
  final String? galleryArtwork;
  final bool logoOverridden;
  static String? publicImage(Object? value) {
    if (value is! String) return null;
    final uri = Uri.tryParse(value);
    if (uri == null ||
        uri.scheme != 'https' ||
        uri.userInfo.isNotEmpty ||
        uri.hasPort ||
        uri.hasFragment ||
        uri.hasQuery)
      return null;
    final allowed = uri.host == 'img.festapp.net'
        ? RegExp(r'^/(images|assets)/')
        : uri.host == 'a.img.festapp.net'
        ? RegExp(r'^/images/')
        : null;
    if (allowed?.hasMatch(uri.path) != true) return null;
    return uri.replace(queryParameters: {'f': 'png'}).toString();
  }

  factory GoogleWalletAppearance.fromTicket(
    Map<String, dynamic> feature, [
    Map<String, dynamic> data = const {},
    bool apple = false,
  ]) {
    final type = feature['ticket_type'] == 'named' ? 'named' : 'wide';
    final template =
        ((feature['layout'] as Map?)?['templates'] as Map?)?[type] as Map?;
    final overrides = feature['wallet_appearance'] as Map? ?? const {};
    final gradient = template?['canvasGradient'];
    final firstStop = gradient is List ? gradient.firstOrNull : null;
    String? color(Object? color) =>
        color is String && RegExp(r'^#?[a-fA-F0-9]{6}$').hasMatch(color)
        ? '#${color.replaceFirst('#', '').toLowerCase()}'
        : null;
    final artwork = overrides.containsKey('hero_image')
        ? overrides['hero_image']
        : feature['background'];
    final publicArtwork = publicImage(artwork);
    final transparent =
        template?['canvasOpacity'] == 0 ||
        template?['canvasColor'] == 'transparent';
    final inheritedColor = apple
        ? (transparent
                  ? null
                  : color(firstStop) ?? color(template?['canvasColor'])) ??
              color(feature['lightColor'])
        : color(template?['canvasColor'] ?? firstStop ?? feature['lightColor']);
    return GoogleWalletAppearance(
      logoOverridden: overrides.containsKey('logo'),
      backgroundColor: overrides.containsKey('background_color')
          ? color(overrides['background_color'])
          : inheritedColor,
      logo: publicImage(
        overrides.containsKey('logo') ? overrides['logo'] : data['logo'],
      ),
      heroImage: apple && publicArtwork != null
          ? '$publicArtwork&w=300'
          : publicArtwork,
      galleryArtwork:
          apple &&
              !overrides.containsKey('hero_image') &&
              artwork is String &&
              artwork.startsWith('https://img.festapp.net/ticket-presets/v1/')
          ? artwork
          : null,
    );
  }
  Map<String, dynamic> toJson() => {
    if (backgroundColor != null) 'backgroundColor': backgroundColor,
    if (logo != null) 'logo': logo,
    if (heroImage != null) 'heroImage': heroImage,
  };
}
