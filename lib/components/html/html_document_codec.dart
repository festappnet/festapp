import 'package:html/dom.dart' as dom;
import 'package:html/parser.dart' as parser;
import 'package:csslib/parser.dart' as css;
import 'package:csslib/visitor.dart' as css_ast;

import 'app_content_policy.g.dart';

enum HtmlContentProfile { appContent, songContent, emailContent }

/// Adds contact links to displayed text without changing attributes or styling.
String linkifyHtmlText(String html) {
  final fullDocument =
      RegExp(r'<!doctype\s|<(?:html|head|body)(?:\s|>)', caseSensitive: false)
          .hasMatch(html);
  final dom.Node root =
      fullDocument ? parser.parse(html) : parser.parseFragment(html);
  return _linkifyHtmlRoot(root) ? _serialize(root) : html;
}

final _contactPattern = RegExp(
  r'(https?://[^\s<>]+|www\.[^\s<>]+)|'
  r'([A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,})|'
  r'(?<![\w+])((?:\+|00)\d{1,3}[ \u00a0.-]?(?:\d[ \u00a0.-]?){6,11}\d|\d{3}[ \u00a0.-]?\d{3}[ \u00a0.-]?\d{3})(?![\w])',
  caseSensitive: false,
);

bool _linkifyHtmlRoot(dom.Node root) {
  var changed = false;
  void visit(dom.Node parent) {
    for (final child in List<dom.Node>.of(parent.nodes)) {
      if (child is dom.Element) {
        if (!{
          'a',
          'pre',
          'code',
          'style',
          'head',
          'script',
          'textarea',
          'button'
        }.contains(child.localName)) {
          visit(child);
        }
      } else if (child is dom.Text && !child.data.contains('{{')) {
        final replacement = <dom.Node>[];
        var offset = 0;
        for (final match in _contactPattern.allMatches(child.data)) {
          var value = match.group(0)!;
          final trailing = match.group(1) != null
              ? RegExp(r'[.,;!?)]+$').firstMatch(value)?.group(0) ?? ''
              : '';
          value = value.substring(0, value.length - trailing.length);
          final String url;
          if (match.group(1) != null) {
            url = value.toLowerCase().startsWith('www.')
                ? 'https://$value'
                : value;
          } else if (match.group(2) != null) {
            url = 'mailto:$value';
          } else {
            var number = value.replaceAll(RegExp(r'[\s.-]'), '');
            if (number.startsWith('00')) number = '+${number.substring(2)}';
            final digits = number.replaceAll('+', '');
            if (digits.length < 7 || digits.length > 15) continue;
            url = 'tel:$number';
          }
          replacement.add(dom.Text(child.data.substring(offset, match.start)));
          replacement.add(dom.Element.tag('a')
            ..attributes['href'] = url
            ..text = value);
          if (trailing.isNotEmpty) replacement.add(dom.Text(trailing));
          offset = match.end;
        }
        if (offset > 0) {
          replacement.add(dom.Text(child.data.substring(offset)));
          final index = parent.nodes.indexOf(child);
          child.remove();
          parent.nodes.insertAll(index, replacement);
          changed = true;
        }
      }
    }
  }

  visit(root);
  return changed;
}

/// App descriptions inherit the configured font and theme, including legacy
/// HTML and pasted content. Songs and emails retain their authored styles.
String normalizeHtmlContentStyles(String html, HtmlContentProfile profile) {
  if (profile != HtmlContentProfile.appContent) return html;
  final fullDocument = RegExp(
    r'<!doctype\s|<(?:html|head|body)(?:\s|>)',
    caseSensitive: false,
  ).hasMatch(html);
  final dom.Node root = fullDocument
      ? parser.parse(html)
      : parser.parseFragment(html);
  final baseline = _serialize(root);
  void visit(dom.Node parent) {
    for (final child in List<dom.Node>.of(parent.nodes)) {
      if (child is dom.Element) {
        if (appHtmlRemovedElements.contains(child.localName)) {
          child.remove();
          continue;
        }
        _normalizeAppElementStyles(child);
        for (final attribute in appHtmlRemovedAttributes) {
          child.attributes.remove(attribute);
        }
        visit(child);
      }
    }
  }

  visit(root);
  final result = _serialize(root);
  return result == baseline ? html : result;
}

// Parse declarations so semicolons in strings and CSS comments cannot bypass
// the app policy. Unrelated safe layout declarations retain their source text.
void _normalizeAppElementStyles(dom.Element element) {
  final source = element.attributes['style'];
  if (source == null) return;
  final errors = <css.Message>[];
  final sheet = css.parse('x {$source}', errors: errors);
  if (errors.isNotEmpty) {
    element.attributes.remove('style');
    return;
  }
  final declarations = sheet.topLevels
      .whereType<css_ast.RuleSet>()
      .expand((rule) => rule.declarationGroup.declarations)
      .whereType<css_ast.Declaration>()
      .toList();
  final values = <String, ({String value, bool important})>{};
  void set(String property, String value, bool important) {
    if (values[property]?.important != true || important) {
      values[property] = (value: value, important: important);
    }
  }

  for (final declaration in declarations) {
    final property = declaration.property.toLowerCase();
    final raw = declaration.span.text;
    final value = raw
        .substring(raw.indexOf(':') + 1)
        .replaceAll(RegExp(r'/\*[\s\S]*?\*/'), '')
        .replaceFirst(RegExp(r'!\s*important\s*$', caseSensitive: false), '')
        .trim()
        .toLowerCase();
    if (property == 'font') {
      // Only style/weight survive the font shorthand; the app owns the family.
      final prefix = value
          .split(RegExp(r'(?:\d*\.)?\d+(?:px|pt|em|rem|%|pc|in|cm|mm)\b'))
          .first;
      final tokens = prefix.split(RegExp(r'\s+'));
      set(
        'font-weight',
        tokens.firstWhere(
          (token) => appHtmlEmphasis
              .firstWhere((rule) => rule.property == 'font-weight')
              .values
              .contains(token),
          orElse: () => 'normal',
        ),
        declaration.important,
      );
      set(
        'font-style',
        tokens.firstWhere(
          (token) => {'italic', 'oblique'}.contains(token),
          orElse: () => 'normal',
        ),
        declaration.important,
      );
    } else {
      set(
        property == 'text-decoration' ? 'text-decoration-line' : property,
        value,
        declaration.important,
      );
    }
  }
  final tags = <String>[];
  final converted = <String>{};
  for (final rule in appHtmlEmphasis) {
    final tokens = (values[rule.property]?.value ?? '').split(RegExp(r'\s+'));
    if (tokens.any(rule.values.contains)) {
      tags.add(rule.tag);
      converted.add(rule.property);
      if (rule.property == 'text-decoration-line') {
        converted.add('text-decoration');
      }
    }
  }
  final retained = declarations
      .where((declaration) {
        final property = declaration.property.toLowerCase();
        return !appHtmlRemovedProperties.contains(property) &&
            !converted.contains(property);
      })
      .map((declaration) => declaration.span.text)
      .join(';');
  if (retained.isEmpty) {
    element.attributes.remove('style');
  } else {
    element.attributes['style'] = retained;
  }
  _wrapAppEmphasis(element, tags);
}

// Wrap inline runs, keeping lists, tables and other block structure valid.
void _wrapAppEmphasis(dom.Element element, List<String> tags) {
  if (tags.isEmpty) return;
  final run = <dom.Node>[];
  void flush() {
    if (run.isEmpty) return;
    final index = element.nodes.indexOf(run.first);
    dom.Element? outer;
    dom.Element? inner;
    for (final tag in tags) {
      final wrapper = dom.Element.tag(tag);
      if (inner != null) inner.nodes.add(wrapper);
      outer ??= wrapper;
      inner = wrapper;
    }
    for (final node in run) {
      node.remove();
      inner!.nodes.add(node);
    }
    element.nodes.insert(index, outer!);
    run.clear();
  }

  for (final child in List<dom.Node>.of(element.nodes)) {
    if (child is dom.Element &&
        appHtmlBlockElements.contains(child.localName)) {
      flush();
      _wrapAppEmphasis(child, tags);
    } else {
      run.add(child);
    }
  }
  flush();
}

/// Apply the same app styles at export and normalize contact links on edits.
String applyHtmlContentProfile(String html, HtmlContentProfile profile) {
  if (profile != HtmlContentProfile.appContent) return html;
  final root = HtmlDocumentCodec.decode(
    normalizeHtmlContentStyles(html, profile),
  ).copyRoot();
  _linkifyHtmlRoot(root);
  return _serialize(root);
}

/// The HTML envelope for an editor session. Super Editor must map editable
/// text to these stable slots instead of round-tripping the layout via Markdown.
/// This layer has no Flutter, clipboard, upload, or persistence side effects.
class HtmlDocumentCodec {
  static HtmlDocumentDraft decode(String? html, {Uri? sourceBase}) {
    final original = html ?? '';
    final fullDocument = RegExp(
      r'<!doctype\s|<(?:html|head|body)(?:\s|>)',
      caseSensitive: false,
    ).hasMatch(original);
    final dom.Node root =
        fullDocument ? parser.parse(original) : parser.parseFragment(original);
    final beforeSanitization = _serialize(root);
    _sanitize(root, sourceBase);
    return HtmlDocumentDraft._(
      root,
      beforeSanitization == _serialize(root) ? original : _serialize(root),
    );
  }
}

/// Mutable DOM owned by one edit session, never a persisted document format.
/// Untouched safe HTML is returned byte-for-byte, including whitespace.
class HtmlDocumentDraft {
  HtmlDocumentDraft._(this._root, this._original) {
    _baseline = _serialize(_root);
    void visit(dom.Node node) {
      if (node is dom.Text && node.data.isNotEmpty && !_isStyleText(node)) {
        final slot = HtmlTextSlot._('text-${_texts.length}', node);
        _texts[slot.id] = slot;
      } else if (node is dom.Element && node.localName == 'img') {
        final image = HtmlImageSlot._('image-${_images.length}', node);
        _images[image.id] = image;
      }
      for (final child in node.nodes) {
        visit(child);
      }
    }

    visit(_root);
  }

  final dom.Node _root;
  final String _original;
  late final String _baseline;
  final _texts = <String, HtmlTextSlot>{};
  final _images = <String, HtmlImageSlot>{};

  Iterable<HtmlTextSlot> get textSlots => _texts.values;
  Iterable<HtmlImageSlot> get imageSlots => _images.values;

  /// Internal module seam for the editor node mapper. The caller owns the copy.
  dom.Node copyRoot() => _root.clone(true);

  /// Call on Apply/Save, not on every widget build or keystroke.
  String encode() {
    final current = _serialize(_root);
    return current == _baseline ? _original : current;
  }

  void replaceText(String slotId, String value) {
    final slot = _texts[slotId];
    if (slot == null) throw ArgumentError.value(slotId, 'slotId');
    // DOM assignment escapes once and keeps ancestor spans, links, table cells
    // and their styles. No UTF-8/string-offset patching of the source HTML.
    slot._node.data = value;
  }

  void replaceImageSource(String slotId, String source) {
    final slot = _images[slotId];
    if (slot == null) throw ArgumentError.value(slotId, 'slotId');
    if (!_safeUrl(source, image: true)) {
      throw ArgumentError.value(source, 'source', 'Unsafe image source');
    }
    slot._node.attributes['src'] = source;
  }

  void removeImageAlternatives(String slotId) {
    final slot = _images[slotId];
    if (slot == null) throw ArgumentError.value(slotId, 'slotId');
    slot._node.attributes.remove('srcset');
    slot._node.attributes.remove('data-src');
  }
}

class HtmlTextSlot {
  HtmlTextSlot._(this.id, this._node);
  final String id;
  final dom.Text _node;
  String get text => _node.data;
}

class HtmlImageSlot {
  HtmlImageSlot._(this.id, this._node);
  final String id;
  final dom.Element _node;
  Map<String, String> get attributes => Map.unmodifiable({
        for (final entry in _node.attributes.entries)
          entry.key.toString(): entry.value,
      });
  String? get source => _node.attributes['src'];
  bool get hasUnresolvedSource {
    final value = source;
    if (value == null || value.isEmpty) return true;
    final uri = Uri.tryParse(value);
    return uri == null || !uri.hasScheme;
  }
}

String _serialize(dom.Node root) {
  if (root is dom.Document) return root.outerHtml;
  return (root as dom.DocumentFragment).outerHtml;
}

bool _isStyleText(dom.Text node) =>
    node.parentNode is dom.Element &&
    (node.parentNode as dom.Element).localName == 'style';

// Preserve safe layout/typography while excluding executable embedding and
// form controls. Paste and stored HTML use the same parsing boundary.
const _allowedTags = {
  'html',
  'head',
  'body',
  'title',
  'style',
  'p',
  'div',
  'span',
  'br',
  'hr',
  'h1',
  'h2',
  'h3',
  'h4',
  'h5',
  'h6',
  'strong',
  'b',
  'em',
  'i',
  'u',
  's',
  'strike',
  'del',
  'ins',
  'sub',
  'sup',
  'a',
  'img',
  'blockquote',
  'pre',
  'code',
  'ul',
  'ol',
  'li',
  'table',
  'thead',
  'tbody',
  'tfoot',
  'tr',
  'th',
  'td',
  'caption',
  'colgroup',
  'col',
  'section',
  'article',
  'header',
  'footer',
  'main',
  'aside',
  'figure',
  'figcaption',
  'dl',
  'dt',
  'dd',
  'small',
  'mark',
  'font',
  'center',
  'address',
  'abbr',
  'wbr',
};
const _allowedAttributes = {
  'id',
  'class',
  'style',
  'title',
  'lang',
  'dir',
  'role',
  'href',
  'target',
  'rel',
  'src',
  'srcset',
  'alt',
  'width',
  'height',
  'align',
  'valign',
  'bgcolor',
  'color',
  'face',
  'size',
  'border',
  'cellpadding',
  'cellspacing',
  'colspan',
  'rowspan',
  'scope',
  'start',
  'value',
  'type',
  'reversed',
  'loading',
  'decoding',
  'data-list',
  'data-src',
  'data-indent',
  'aria-label',
  'aria-hidden',
};
const _dropContents = {
  'script',
  'iframe',
  'object',
  'embed',
  'svg',
  'math',
  'template',
  'form',
  'input',
  'button',
  'textarea',
  'select',
  'link',
  'meta',
  'base',
};

void _sanitize(dom.Node node, Uri? sourceBase) {
  // Snapshot because disallowed elements may be unwrapped or removed.
  for (final child in List<dom.Node>.of(node.nodes)) {
    if (child is! dom.Element) continue;
    final tag = child.localName;
    if (_dropContents.contains(tag)) {
      child.remove();
      continue;
    }
    _sanitize(child, sourceBase);
    if (!_allowedTags.contains(tag)) {
      final index = node.nodes.indexOf(child);
      final contents = List<dom.Node>.of(child.nodes);
      child.remove();
      node.nodes.insertAll(index, contents);
      continue;
    }
    if (tag == 'style' && !_safeCss(child.text)) {
      child.remove();
      continue;
    }
    for (final attribute in List<Object>.of(child.attributes.keys)) {
      final name = attribute.toString().toLowerCase();
      final value = child.attributes[attribute]!;
      final image = name == 'src' || name == 'data-src';
      if (!_allowedAttributes.contains(name) ||
          (name == 'style' && !_safeCss(value)) ||
          ((name == 'href' || image) && !_safeUrl(value, image: image)) ||
          (name == 'srcset' && !_safeSrcSet(value))) {
        child.attributes.remove(attribute);
        continue;
      }
      if ((name == 'href' || image) &&
          sourceBase != null &&
          !value.contains('{{') &&
          !Uri.parse(value).hasScheme) {
        final resolved = sourceBase.resolve(value).toString();
        if (_safeUrl(resolved, image: image)) {
          child.attributes[attribute] = resolved;
        } else {
          child.attributes.remove(attribute);
        }
      }
    }
  }
}

bool _safeCss(String value) {
  // Escapes/comments can conceal executable CSS. Preserve ordinary inline
  // styles and safe email stylesheets, reject indirect network/input behavior.
  final lower = value.toLowerCase();
  return !lower.contains('\\') &&
      !lower.contains('/*') &&
      !RegExp(r'url\s*\(|expression\s*\(|@import|behavior\s*:|-moz-binding')
          .hasMatch(lower);
}

bool _safeUrl(String value, {required bool image}) {
  if (RegExp(r'[\x00-\x20\x7f]').hasMatch(value)) return false;
  if (value.contains('{{')) {
    // Only a complete placeholder can act as a URL; never trust a prefix
    // such as javascript:{{value}} because it includes a template variable.
    return !image && RegExp(r'^\{\{[A-Za-z][A-Za-z0-9_]*\}\}$').hasMatch(value);
  }
  final uri = Uri.tryParse(value);
  if (uri == null) return false;
  if (!uri.hasScheme) return true; // Unresolved, never guess a base URL.
  if (uri.scheme == 'http' || uri.scheme == 'https') {
    return uri.host.isNotEmpty && uri.userInfo.isEmpty;
  }
  if (!image) return uri.scheme == 'mailto' || uri.scheme == 'tel';
  if (uri.scheme != 'data' || value.length > 14 * 1024 * 1024) return false;
  return RegExp(
    r'^data:image/(?:png|jpeg|gif|webp);base64,[A-Za-z0-9+/]*={0,2}$',
    caseSensitive: false,
  ).hasMatch(value);
}

bool _safeSrcSet(String value) => value.split(',').every((candidate) {
      final parts = candidate.trim().split(RegExp(r'\s+'));
      return parts.isNotEmpty &&
          _safeUrl(parts.first, image: true) &&
          parts.length <= 2 &&
          (parts.length == 1 ||
              RegExp(r'^\d+(?:\.\d+)?[wx]$').hasMatch(parts.last));
    });
