import 'package:flutter/material.dart';
import 'package:flutter_widget_from_html/flutter_widget_from_html.dart';
import 'package:html/parser.dart' as parser;

/// Retains the server's email HTML and styles rather than the app's theme.
class SetupEmailDocument extends StatelessWidget {
  const SetupEmailDocument({super.key, required this.html});
  final String html;
  String _inertHtml() {
    final document = parser.parse(html);
    var changed = false;
    for (final node in document.querySelectorAll(
        'script,iframe,object,embed,form,input,button,video,audio,source')) {
      node.remove();
      changed = true;
    }
    for (final element in document.querySelectorAll('*')) {
      for (final name in element.attributes.keys.toList()) {
        if (name.toString().toLowerCase().startsWith('on')) {
          element.attributes.remove(name);
          changed = true;
        }
      }
    }
    return changed ? document.outerHtml : html;
  }

  @override
  Widget build(BuildContext context) => ColoredBox(
        color: Colors.white,
        child: HtmlWidget(
          _inertHtml(),
          textStyle: const TextStyle(
              fontFamily: 'sans-serif', fontSize: 16, color: Colors.black),
          onTapUrl: (_) async => true,
        ),
      );
}
