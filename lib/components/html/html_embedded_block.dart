import 'package:flutter/widgets.dart';
import 'package:html/parser.dart' as parser;

/// A domain-owned live widget stored as an atomic block in rich HTML.
class HtmlEmbeddedBlock {
  const HtmlEmbeddedBlock({required this.cssClass, required this.builder});
  final String cssClass;
  final WidgetBuilder builder;

  String get html => '<div class="html-editor-block $cssClass"></div>';

  bool matches(String html) =>
      parser
          .parseFragment(html)
          .querySelector('div.html-editor-block.$cssClass') !=
      null;
}
