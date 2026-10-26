import 'occasion_setup_strings.dart';
import 'dart:js_interop';
import 'package:material_ui/material_ui.dart';
import 'package:web/web.dart' as web;

/// The exact server-rendered email document, isolated from application CSS.
/// Scripts/forms are disabled, and the preview has no clickable actions.
class SetupEmailDocument extends StatefulWidget {
  const SetupEmailDocument({super.key, required this.html});
  final String html;
  @override
  State<SetupEmailDocument> createState() => _SetupEmailDocumentState();
}

class _SetupEmailDocumentState extends State<SetupEmailDocument> {
  double _height = 640;
  web.ResizeObserver? _observer;
  web.HTMLIFrameElement? _frame;
  void _measure() {
    if (!mounted) return;
    final next = (_frame?.contentDocument?.documentElement?.scrollHeight ?? 640)
        .toDouble();
    if ((next - _height).abs() > 1) setState(() => _height = next);
  }

  @override
  void dispose() {
    _observer?.disconnect();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => SizedBox(
        height: _height,
        width: double.infinity,
        child: HtmlElementView.fromTagName(
          key: ValueKey(widget.html),
          tagName: 'iframe',
          onElementCreated: (element) {
            _observer?.disconnect();
            final frame = element as web.HTMLIFrameElement;
            _frame = frame;
            frame.title = OccasionSetupStrings.ui('actual_email_preview');
            frame.referrerPolicy = 'no-referrer';
            frame.tabIndex = -1;
            frame.setAttribute('sandbox', 'allow-same-origin');
            frame.style
              ..width = '100%'
              ..height = '100%'
              ..border = '0'
              ..backgroundColor = 'white'
              ..pointerEvents = 'none';
            frame.addEventListener(
                'load',
                ((web.Event event) {
                  if (!mounted || _frame != frame) return;
                  final document = frame.contentDocument;
                  if (document?.documentElement == null) return;
                  _observer = web.ResizeObserver(
                      ((JSArray<web.ResizeObserverEntry> entries,
                          web.ResizeObserver observer) {
                    _measure();
                  }).toJS)
                    ..observe(document!.documentElement!);
                  _measure();
                }).toJS);
            frame.srcdoc = widget.html.toJS;
          },
        ),
      );
}
