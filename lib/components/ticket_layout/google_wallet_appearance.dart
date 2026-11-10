/// Compatible native Google Wallet fields, independent of PDF geometry and fonts.
class GoogleWalletAppearance {
  const GoogleWalletAppearance({
    this.backgroundColor,
    this.logo,
    this.heroImage,
  });
  final String? backgroundColor, logo, heroImage;
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
  ]) {
    final type = feature['ticket_type'] == 'named' ? 'named' : 'wide';
    final template =
        ((feature['layout'] as Map?)?['templates'] as Map?)?[type] as Map?;
    final overrides = feature['wallet_appearance'] as Map? ?? const {};
    final color = overrides.containsKey('background_color')
        ? overrides['background_color']
        : template?['canvasColor'] ??
              (template?['canvasGradient'] as List?)?.firstOrNull ??
              feature['lightColor'];
    final parsed =
        color is String && RegExp(r'^#?[a-fA-F0-9]{6}$').hasMatch(color)
        ? '#${color.replaceFirst('#', '').toLowerCase()}'
        : null;
    return GoogleWalletAppearance(
      backgroundColor: parsed,
      logo: publicImage(
        overrides.containsKey('logo') ? overrides['logo'] : data['logo'],
      ),
      heroImage: publicImage(
        overrides.containsKey('hero_image')
            ? overrides['hero_image']
            : feature['background'],
      ),
    );
  }
  Map<String, dynamic> toJson() => {
    if (backgroundColor != null) 'backgroundColor': backgroundColor,
    if (logo != null) 'logo': logo,
    if (heroImage != null) 'heroImage': heroImage,
  };
}
