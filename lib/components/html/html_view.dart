import 'dart:async';
import 'html_document_codec.dart';
import 'html_text_style.dart';
import 'dart:convert';
import 'dart:typed_data';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_widget_from_html/flutter_widget_from_html.dart';
import 'package:fstapp/router_service.dart';
import 'package:fstapp/app_config.dart';
import 'package:fstapp/theme_config.dart';
import 'package:fwfh_cached_network_image/fwfh_cached_network_image.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:cached_network_image_platform_interface/cached_network_image_platform_interface.dart';
import 'package:flutter_cache_manager/flutter_cache_manager.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:youtube_player_flutter/youtube_player_flutter.dart';
import 'package:fstapp/services/launch_url_service.dart';
import 'package:fstapp/services/connectivity_service.dart';

import '../images/zoomable_image/zoomable_image.dart';

/// Factory to enable cached network images in HtmlWidget
class MyWidgetFactory extends WidgetFactory with CachedNetworkImageFactory {}

@visibleForTesting
String? youtubeVideoIdFromUrl(String url) {
  final uri = Uri.tryParse(url.trim());
  if (uri != null) {
    final host = uri.host.toLowerCase().replaceFirst(RegExp(r'^www\.'), '');
    if (host == 'youtu.be' && uri.pathSegments.isNotEmpty) {
      final id = uri.pathSegments.first;
      if (id.length == 11) return id;
    }
    if (host == 'youtube.com' ||
        host == 'm.youtube.com' ||
        host == 'music.youtube.com' ||
        host == 'youtube-nocookie.com') {
      final queryId = uri.queryParameters['v'];
      if (queryId?.length == 11) return queryId;
      if (uri.pathSegments.length >= 2 &&
          const {'shorts', 'embed'}.contains(uri.pathSegments.first)) {
        final id = uri.pathSegments[1];
        if (id.length == 11) return id;
      }
    }
  }
  return YoutubePlayerController.convertUrlToId(url);
}

class HtmlWithAppLinksWidget extends HtmlWidget {
  HtmlWithAppLinksWidget(
    this.context,
    super.html, {
    super.key,
    required RenderMode renderMode,
    super.textStyle,
    super.customWidgetBuilder,
    super.customStylesBuilder,
  }) : super(factoryBuilder: () => MyWidgetFactory());

  final BuildContext context;

  @override
  FutureOr<bool> Function(String)? get onTapUrl => (url) {
        if (AppConfig.compatibleUrls()
                .where((u) => u.isNotEmpty)
                .any((u) => url.startsWith(u)) ||
            url.contains("localhost")) {
          RouterService.navigate(context, url);
          return true;
        }
        super.onTapUrl?.call(url);
        return false;
      };

  @override
  void Function(ImageMetadata)? get onTapImage => (_) {};
}

class HtmlView extends StatefulWidget {
  final String html;
  final double fontSize;
  final bool isSelectable;
  final Color? color;
  final Uint8List? Function(String source)? imageBytesResolver;

  /// Optional overrides; if you don’t pass them, we’ll fall back to the scope.
  final VoidCallback? twoFingersOn;
  final VoidCallback? twoFingersOff;

  @visibleForTesting
  final bool? offlineOverride;

  const HtmlView({
    super.key,
    required this.html,
    this.fontSize = 18,
    this.isSelectable = false,
    this.color,
    this.imageBytesResolver,
    this.twoFingersOn,
    this.twoFingersOff,
    this.offlineOverride,
  });

  @override
  State<HtmlView> createState() => _HtmlViewState();
}

class _HtmlViewState extends State<HtmlView> {
  @override
  Widget build(BuildContext context) {
    final offlineOverride = widget.offlineOverride;
    if (offlineOverride != null) {
      return _buildContent(context, offlineOverride);
    }
    return ValueListenableBuilder<bool>(
      valueListenable: ConnectivityService.isOfflineNotifier,
      builder: (context, isOffline, _) => _buildContent(context, isOffline),
    );
  }

  Widget _buildContent(BuildContext context, bool isOffline) {
    final textColor = widget.color ?? ThemeConfig.defaultHtmlViewColor(context);
    final linkColor = colorToRgbString(ThemeConfig.htmlLinkColor(context));

    Widget content = HtmlWithAppLinksWidget(
      context,
      linkifyHtmlText(widget.html),
      renderMode: RenderMode.listView,
      textStyle:
          htmlTextStyle(context, fontSize: widget.fontSize, color: textColor),
      customStylesBuilder: (el) {
        // Handle alignment classes from rich text editors like Quill.js
        if (el.attributes['class'] != null) {
          final classes = el.attributes['class']!.split(' ');
          if (classes.contains('ql-align-center')) {
            return {'text-align': 'center'};
          }
          if (classes.contains('ql-align-right')) {
            return {'text-align': 'right'};
          }
          if (classes.contains('ql-align-justify')) {
            return {'text-align': 'justify'};
          }
        }
        switch (el.localName) {
          case 'a':
            return {'color': linkColor};
          case 'li':
            if (el.attributes['data-list'] == 'bullet') {
              return {'list-style-type': 'disc'};
            }
        }
        return null;
      },
      customWidgetBuilder: (el) {
        if (el.localName == 'img') {
          final src = el.attributes['src'] ?? el.attributes['data-src'];
          if (src == null || src.isEmpty)
            return const Icon(Icons.broken_image_outlined);
          final bytes = widget.imageBytesResolver?.call(src);
          final img = bytes != null
              ? Image.memory(bytes)
              : src.startsWith('data:image/')
                  ? Image.memory(base64Decode(src.split(',').last))
                  : CachedNetworkImage(
                      imageUrl: src,
                      cacheManager: DefaultCacheManager(),
                      imageRenderMethodForWeb: ImageRenderMethodForWeb.HttpGet,
                    );
          return Align(
            alignment: Alignment.center,
            heightFactor: 1,
            child: ZoomableImage(
              onTwoFingerStart: widget.twoFingersOn,
              onTwoFingerEnd: widget.twoFingersOff,
              child: ClipRRect(
                borderRadius: BorderRadius.circular(8.0),
                child: img,
              ),
            ),
          );
        }

        if (!kIsWeb && el.localName == 'a') {
          final url = el.attributes['href']!;
          final vid = youtubeVideoIdFromUrl(url);
          if (vid != null) {
            return _YoutubeEmbed(
              key: ValueKey('youtube:$url'),
              url: url,
              videoId: vid,
              isOffline: isOffline,
            );
          }
        }

        return null;
      },
    );

    return widget.isSelectable
        ? SelectionArea(
            focusNode: FocusNode(),
            selectionControls: materialTextSelectionControls,
            child: content,
          )
        : content;
  }

  String colorToRgbString(Color? c) {
    if (c == null) return '';
    return 'rgb(${(c.r * 255).round()}, ${(c.g * 255).round()}, ${(c.b * 255).round()})';
  }
}

class _YoutubeEmbed extends StatefulWidget {
  const _YoutubeEmbed({
    super.key,
    required this.url,
    required this.videoId,
    required this.isOffline,
  });

  final String url;
  final String videoId;
  final bool isOffline;

  @override
  State<_YoutubeEmbed> createState() => _YoutubeEmbedState();
}

class _YoutubeEmbedState extends State<_YoutubeEmbed> {
  static final Future<String> _appOrigin = PackageInfo.fromPlatform().then(
    (info) => Uri(scheme: 'https', host: info.packageName).toString(),
  );

  YoutubePlayerController? _controller;
  int _controllerGeneration = 0;

  @override
  void initState() {
    super.initState();
    unawaited(_updateController());
  }

  @override
  void didUpdateWidget(covariant _YoutubeEmbed oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.videoId != widget.videoId ||
        oldWidget.isOffline != widget.isOffline) {
      _disposeController();
      unawaited(_updateController());
    }
  }

  Future<void> _updateController() async {
    if (widget.isOffline) return;
    final generation = ++_controllerGeneration;
    final origin = await _appOrigin;
    if (!mounted || generation != _controllerGeneration || widget.isOffline) {
      return;
    }

    _controller = YoutubePlayerController.fromVideoId(
      videoId: widget.videoId,
      autoPlay: false,
      params: const YoutubePlayerParams(
        showControls: true,
        showFullscreenButton: true,
        playsInline: true,
        privacyEnhancedMode: false,
      ).copyWith(origin: origin),
    );
    setState(() {});
  }

  void _disposeController() {
    _controllerGeneration++;
    unawaited(_controller?.close());
    _controller = null;
  }

  @override
  void dispose() {
    _disposeController();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final controller = _controller;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (controller != null)
          YoutubePlayer(
            controller: controller,
          ),
        OutlinedButton.icon(
          onPressed: widget.isOffline
              ? null
              : () => LaunchUrlService.openExternalUrl(widget.url),
          icon: Icon(widget.isOffline ? Icons.cloud_off : Icons.open_in_new),
          label: Text(widget.url),
        ),
      ],
    );
  }
}
