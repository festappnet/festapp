import 'dart:async';
import 'dart:js_interop';

import 'package:easy_localization/easy_localization.dart';
import 'package:material_ui/material_ui.dart';
import 'package:web/web.dart' as web;

import '../../database_tables/tb.dart';
import '../features/feature_constants.dart';
import '../features/feature_service.dart';
import '../features/form_feature.dart';
import '../occasion/occasion_model.dart';
import 'occasion_catalog_preview_native.dart' as fallback;
import 'occasion_settings_strings.dart';

/// Hosts the public web card renderer. Only draft data crosses the boundary;
/// layout, formatting, fonts and CSS come from the public catalogue build.
class OccasionCatalogPreview extends StatefulWidget {
  const OccasionCatalogPreview({super.key, required this.occasion});
  final OccasionModel occasion;
  @override
  State<OccasionCatalogPreview> createState() => _OccasionCatalogPreviewState();
}

class _OccasionCatalogPreviewState extends State<OccasionCatalogPreview> {
  web.HTMLIFrameElement? _frame;
  late final JSFunction _messageListener;
  double _height = 300;
  bool _ready = false;

  @override
  void initState() {
    super.initState();
    _messageListener = ((web.MessageEvent event) {
      final frame = _frame;
      if (!mounted ||
          frame == null ||
          event.source != frame.contentWindow ||
          event.origin != web.window.location.origin) {
        return;
      }
      final data = event.data.dartify();
      if (data is! Map) return;
      if (data['type'] == 'festapp-occasion-card-ready') {
        if (!_ready) {
          frame.style.opacity = '1';
          setState(() => _ready = true);
        }
        _sendDraft();
      } else if (data['type'] == 'festapp-occasion-card-height') {
        final height = data['height'];
        if (height is num &&
            height.isFinite &&
            height > 0 &&
            height < 10000 &&
            (height - _height).abs() > 1) {
          setState(() => _height = height.toDouble());
        }
      }
    }).toJS;
    web.window.addEventListener('message', _messageListener);
  }

  void _sendDraft() {
    final frame = _frame;
    if (!_ready || !mounted || frame == null) return;
    final dark = Theme.of(context).brightness == Brightness.dark;
    // A transparent iframe needs the same color scheme as its document.
    frame.style.colorScheme = dark ? 'dark' : 'light';
    final occasion = widget.occasion;
    final data = occasion.toJson();
    final form = FeatureService.getFeatureDetails(
      FeatureConstants.form,
      features: occasion.features,
    );
    final card = {
      Tb.occasions.title: occasion.title,
      Tb.occasions.link: occasion.link,
      Tb.occasions.start_time: data[Tb.occasions.start_time],
      Tb.occasions.end_time: data[Tb.occasions.end_time],
      Tb.occasions.data: {
        Tb.occasions.data_image: occasion.data?[Tb.occasions.data_image],
      },
      Tb.occasions.features: [
        if (form is FormFeature)
          {
            FeatureConstants.metaCode: form.code,
            FeatureConstants.metaIsEnabled: form.isEnabled,
            FeatureConstants.formExternalPrice: form.formExternalPrice,
          },
      ],
    };
    frame.contentWindow?.postMessage(
      {
        'type': 'festapp-occasion-card-draft',
        'occasion': card,
        'locale': context.locale.toLanguageTag(),
        'dark': dark,
      }.jsify(),
      web.window.location.origin.toJS,
    );
  }

  @override
  void didUpdateWidget(OccasionCatalogPreview oldWidget) {
    super.didUpdateWidget(oldWidget);
    _sendDraft();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    scheduleMicrotask(_sendDraft);
  }

  @override
  void dispose() {
    web.window.removeEventListener('message', _messageListener);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Stack(
    children: [
      if (_ready)
        SizedBox(height: _height, width: double.infinity)
      else
        fallback.OccasionCatalogPreview(occasion: widget.occasion),
      Positioned.fill(
        child: HtmlElementView.fromTagName(
          tagName: 'iframe',
          onElementCreated: (element) {
            final frame = element as web.HTMLIFrameElement;
            _frame = frame;
            frame.title = OccasionSettingsStrings.preview;
            frame.referrerPolicy = 'no-referrer';
            frame.tabIndex = -1;
            frame.style
              ..width = '100%'
              ..height = '100%'
              ..border = '0'
              ..colorScheme = 'light'
              ..opacity = '0'
              ..pointerEvents = 'none';
            frame.src = Uri.base
                .resolve('/occasion-card-preview.html')
                .toString();
          },
        ),
      ),
    ],
  );
}
