import 'dart:convert';

import 'package:flutter/material.dart' show Color, TextStyle;
import 'package:html/dom.dart' as dom;
import 'package:csslib/parser.dart' as css;
import 'package:html/parser.dart' as parser;
import 'package:super_editor/super_editor.dart';

import 'html_document_codec.dart';

/// Maps editable leaf blocks to Super Editor while retaining the surrounding
/// HTML AST (including nested email tables) as the authoritative envelope.
class HtmlEditorDocument {
  HtmlEditorDocument(String? html) {
    final draft = HtmlDocumentCodec.decode(html);
    _original = draft.encode();
    _template = draft.copyRoot();
    final nodes = <DocumentNode>[];

    void add(List<dom.Node> source, DocumentNode node, {dom.Element? wrapper}) {
      final parent = source.first.parentNode!;
      final index = parent.nodes.indexOf(source.first);
      final marker = dom.Comment('html-editor:${node.id}');
      final saved = source.map((n) => n.clone(true)).toList();
      for (final item in source) {
        item.remove();
      }
      parent.nodes.insert(index, marker);
      _envelopes[node.id] = _Envelope(saved, wrapper?.clone(false));
      nodes.add(node);
    }

    void visit(dom.Node parent) {
      for (final child in List<dom.Node>.of(parent.nodes)) {
        if (child is dom.Element) {
          final tag = child.localName!;
          if (tag == 'head' || tag == 'style' || tag == 'title') continue;
          if (tag == 'img') {
            add(
                [child],
                ImageNode(
                    id: Editor.createNodeId(),
                    imageUrl: child.attributes['src'] ??
                        child.attributes['data-src'] ??
                        '',
                    altText: child.attributes['alt'] ?? ''));
          } else if (tag == 'hr') {
            add([child], HorizontalRuleNode(id: Editor.createNodeId()));
          } else if (_blockTags.contains(tag) &&
              !_containsBlocksOrImages(child)) {
            final text = _readInline(child.nodes);
            final id = Editor.createNodeId();
            final metadata = <String, dynamic>{
              'blockType': _blockAttribution(tag),
              'htmlStyles': _inheritedStyles(child),
              if (_alignment(child) != null) 'textAlign': _alignment(child),
            };
            final node = tag == 'li'
                ? ListItemNode(
                    id: id,
                    text: text,
                    itemType: _listType(child),
                    indent: _listIndent(child),
                    metadata: metadata)
                : ParagraphNode(id: id, text: text, metadata: metadata);
            add([child], node, wrapper: child);
          } else if (_inlineTags.contains(tag) && child.nodes.isEmpty) {
            // Standalone line breaks and empty inline wrappers are editable
            // text slots, not opaque decorations that launch another editor.
            add(
                [child],
                ParagraphNode(
                    id: Editor.createNodeId(), text: _readInline([child])));
          } else if (child.nodes.isNotEmpty) {
            visit(child);
          } else {
            // Safe non-text decoration remains a selectable preserved block.
            add(
                [child],
                PreservedHtmlNode(
                    id: Editor.createNodeId(), html: child.outerHtml));
          }
        } else if (child is dom.Text && child.data.trim().isNotEmpty) {
          // Direct text in a complex container (e.g. a td or a nested li).
          // The ancestor envelope preserves cell/list/layout attributes.
          final container = child.parent;
          add(
              [child],
              container?.localName == 'li'
                  ? ListItemNode(
                      id: Editor.createNodeId(),
                      text: AttributedText(child.data),
                      itemType: _listType(container!),
                      indent: _listIndent(container))
                  : ParagraphNode(
                      id: Editor.createNodeId(),
                      text: AttributedText(child.data)));
        }
      }
    }

    visit(_template);
    if (nodes.isEmpty) {
      final node =
          ParagraphNode(id: Editor.createNodeId(), text: AttributedText());
      final parent = _body(_template);
      parent.nodes.add(dom.Comment('html-editor:${node.id}'));
      _envelopes[node.id] = _Envelope([], null);
      nodes.add(node);
    }
    document = MutableDocument(nodes: nodes);
    _baseline = {for (final node in nodes) node.id: _copyNode(node)};
    _initialOrder = nodes.map((n) => n.id).toList();
  }

  late final MutableDocument document;
  late final String _original;
  late final dom.Node _template;
  late final Map<String, DocumentNode> _baseline;
  late final List<String> _initialOrder;
  final _envelopes = <String, _Envelope>{};

  void adoptFragment(HtmlEditorDocument fragment) {
    _envelopes.addAll(fragment._envelopes);
    _baseline.addAll(fragment._baseline);
  }

  bool get isUnchanged =>
      document.length == _initialOrder.length &&
      document.indexed.every((entry) =>
          entry.$2.id == _initialOrder[entry.$1] &&
          _equivalent(_baseline[entry.$2.id]!, entry.$2));

  String encode() {
    if (isUnchanged) return _original;
    final root = _template.clone(true);
    final anchors = <String, dom.Comment>{};
    void find(dom.Node node) {
      if (node is dom.Comment && (node.data ?? '').startsWith('html-editor:')) {
        anchors[node.data!.substring('html-editor:'.length)] = node;
      }
      for (final child in node.nodes) {
        find(child);
      }
    }

    find(root);
    // Reorder slots within their retained container. Moving editable leaves
    // across table cells would destroy layout semantics, so reject that move.
    final positions = {
      for (final entry in document.indexed) entry.$2.id: entry.$1
    };
    final parents = <dom.Node, List<dom.Comment>>{};
    for (final entry in anchors.entries) {
      if (positions.containsKey(entry.key)) {
        (parents[entry.value.parentNode!] ??= []).add(entry.value);
      }
    }
    for (final entry in parents.entries) {
      final slots = entry.value;
      final ordered = List<dom.Comment>.of(slots)
        ..sort((a, b) => positions[a.data!.substring(12)]!
            .compareTo(positions[b.data!.substring(12)]!));
      final indexes =
          slots.map((slot) => entry.key.nodes.indexOf(slot)).toList()..sort();
      for (final slot in slots) {
        slot.remove();
      }
      for (var i = 0; i < ordered.length; i++) {
        entry.key.nodes.insert(indexes[i], ordered[i]);
      }
    }
    var lastPosition = -1;
    void checkOrder(dom.Node node) {
      if (node is dom.Comment && (node.data ?? '').startsWith('html-editor:')) {
        final position = positions[node.data!.substring(12)];
        if (position != null) {
          if (position < lastPosition)
            throw StateError(
                'Move across HTML layout containers is unsupported');
          lastPosition = position;
        }
      }
      for (final child in node.nodes) {
        checkOrder(child);
      }
    }

    checkOrder(root);
    final listElements = <String, dom.Element>{};
    dom.Node? previous;
    for (final node in document) {
      final anchor = anchors.remove(node.id);
      final envelope = _envelopes[node.id];
      final original = _baseline[node.id];
      final output = original != null && _equivalent(original, node)
          ? envelope!.original.map((n) => n.clone(true)).toList()
          : _serializeNode(node, envelope);
      if (node is ListItemNode) {
        final element = output.whereType<dom.Element>().firstOrNull;
        final item =
            element?.localName == 'li' ? element : element?.querySelector('li');
        if (item != null)
          listElements[node.id] = item;
        else if (anchor?.parent?.localName == 'li')
          listElements[node.id] = anchor!.parent!;
      }
      if (anchor != null) {
        final parent = anchor.parentNode!;
        final index = parent.nodes.indexOf(anchor);
        anchor.remove();
        final inserted = _insertableListChildren(parent, output);
        parent.nodes.insertAll(index, inserted);
        if (inserted.isNotEmpty) previous = inserted.last;
      } else {
        // Split/paste nodes follow their preceding node in the same HTML
        // container, so edits inside an email cell stay inside that cell.
        final previousCell =
            previous is dom.Element && {'td', 'th'}.contains(previous.localName)
                ? previous
                : null;
        final parent = previousCell ?? previous?.parentNode ?? _body(root);
        final index = previousCell != null
            ? parent.nodes.length
            : previous == null
                ? 0
                : parent.nodes.indexOf(previous) + 1;
        final inserted = _insertableListChildren(parent, output);
        parent.nodes.insertAll(index, inserted);
        if (inserted.isNotEmpty) previous = inserted.last;
      }
    }
    for (final entry in anchors.entries) {
      final anchor = entry.value;
      final wrapper = _envelopes[entry.key]?.wrapper;
      if (wrapper != null && {'td', 'th'}.contains(wrapper.localName)) {
        final parent = anchor.parentNode!;
        final index = parent.nodes.indexOf(anchor);
        anchor.remove();
        parent.nodes.insert(index, wrapper.clone(false));
      } else {
        anchor.remove();
      }
    }
    for (final node in document.whereType<ListItemNode>()) {
      final original = _baseline[node.id];
      final item = listElements[node.id];
      if (item == null || original is! ListItemNode) continue;
      if (node.indent != original.indent) {
        _moveListIndent(item, node.indent - original.indent, node.type);
        final classes = (item.attributes['class'] ?? '')
            .split(' ')
            .where((c) => !c.startsWith('ql-indent-') && c.isNotEmpty)
            .toList();
        if (classes.isEmpty) {
          item.attributes.remove('class');
        } else {
          item.attributes['class'] = classes.join(' ');
        }
      }
      if (node.type != original.type) _changeListType(item, node.type);
    }
    return root is dom.Document
        ? root.outerHtml
        : (root as dom.DocumentFragment).outerHtml;
  }

  List<dom.Node> _serializeNode(DocumentNode node, _Envelope? envelope) {
    if (node is ImageNode) {
      final image = envelope?.original.firstOrNull is dom.Element
          ? (envelope!.original.first as dom.Element).clone(true)
          : dom.Element.tag('img');
      image.attributes['src'] = node.imageUrl;
      image.attributes['alt'] = node.altText;
      return [image];
    }
    if (node is BitmapImageNode) {
      throw StateError('Bitmap must enter the media draft before HTML export');
    }
    if (node is PreservedHtmlNode)
      return parser.parseFragment(node.html).nodes.toList();
    if (node is HorizontalRuleNode) return [dom.Element.tag('hr')];
    if (node is! TextNode)
      throw StateError('Unsupported HTML node ${node.runtimeType}');
    final inline = parser
        .parseFragment(
            _writeInline(node.text, preformatted: _paragraphTag(node) == 'pre'))
        .nodes
        .toList();
    // A direct text slot retains its surrounding container and inline tags.
    if (envelope != null &&
        envelope.wrapper == null &&
        envelope.original.isNotEmpty) return inline;
    final blockTag = _paragraphTag(node);
    final originalTag = envelope?.wrapper?.localName;
    final cell = originalTag == 'td' || originalTag == 'th';
    final tag = node is ListItemNode
        ? 'li'
        : cell
            ? originalTag!
            : blockTag == 'p' && originalTag == 'div'
                ? 'div'
                : blockTag;
    final wrapper = dom.Element.tag(tag);
    if (envelope?.wrapper != null)
      wrapper.attributes.addAll(envelope!.wrapper!.attributes);
    final align = node.getMetadataValue('textAlign');
    if (align is String &&
        align != _baseline[node.id]?.getMetadataValue('textAlign')) {
      final css = wrapper.attributes['style'] ?? '';
      wrapper.attributes['style'] =
          '${css.replaceAll(RegExp(r'text-align\s*:[^;]+;?'), '')};text-align:$align';
      final classes = (wrapper.attributes['class'] ?? '')
          .split(' ')
          .where((c) => !c.startsWith('ql-align-') && c.isNotEmpty)
          .toList();
      if (classes.isEmpty) {
        wrapper.attributes.remove('class');
      } else {
        wrapper.attributes['class'] = classes.join(' ');
      }
    }
    if (cell && blockTag != 'p') {
      wrapper.nodes.add(dom.Element.tag(blockTag)..nodes.addAll(inline));
    } else {
      wrapper.nodes.addAll(inline);
    }
    if (node is ListItemNode && wrapper.attributes.containsKey('data-list')) {
      wrapper.attributes['data-list'] =
          node.type == ListItemType.ordered ? 'ordered' : 'bullet';
    }
    if (node is ListItemNode && envelope?.wrapper?.localName != 'li') {
      final list =
          dom.Element.tag(node.type == ListItemType.ordered ? 'ol' : 'ul');
      list.nodes.add(wrapper);
      return [list];
    }
    return [wrapper];
  }
}

List<String> _inheritedStyles(dom.Element element) {
  final styles = <String>[];
  for (dom.Element? parent = element; parent != null; parent = parent.parent) {
    if (parent.attributes['style'] != null)
      styles.insert(0, parent.attributes['style']!);
  }
  return styles;
}

TextStyle htmlBlockTextStyler(DocumentNode node, TextStyle base) {
  final styles = node.getMetadataValue('htmlStyles');
  if (styles is! List) return base;
  return htmlInlineTextStyler({
    _HtmlInline(styles
        .whereType<String>()
        .map((style) => dom.Element.tag('span')..attributes['style'] = style)
        .toList())
  }, base);
}

class _Envelope {
  _Envelope(this.original, this.wrapper);
  final List<dom.Node> original;
  final dom.Element? wrapper;
}

List<dom.Node> _insertableListChildren(dom.Node parent, List<dom.Node> output) {
  if (parent is! dom.Element || !{'ul', 'ol'}.contains(parent.localName))
    return output;
  final result = <dom.Node>[];
  for (final node in output) {
    if (node is dom.Element && node.localName == parent.localName) {
      result.addAll(List<dom.Node>.of(node.nodes));
    } else if (node is dom.Element && node.localName != 'li') {
      result.add(dom.Element.tag('li')..nodes.add(node));
    } else {
      result.add(node);
    }
  }
  return result;
}

void _moveListIndent(dom.Element item, int delta, ListItemType type) {
  for (var step = 0; step < delta.abs(); step++) {
    final list = item.parent;
    if (list == null) return;
    if (delta > 0) {
      final index = list.nodes.indexOf(item);
      final previous = list.nodes
          .take(index)
          .whereType<dom.Element>()
          .where((e) => e.localName == 'li')
          .lastOrNull;
      if (previous == null)
        throw StateError('Indent requires a preceding list item');
      final nested =
          dom.Element.tag(type == ListItemType.ordered ? 'ol' : 'ul');
      item.remove();
      nested.nodes.add(item);
      previous.nodes.add(nested);
    } else {
      final parentItem = list.parent;
      final outer = parentItem?.parent;
      if (parentItem?.localName != 'li' || outer == null) break;
      item.remove();
      outer.nodes.insert(outer.nodes.indexOf(parentItem!) + 1, item);
    }
    if (list.children.isEmpty) list.remove();
  }
}

void _changeListType(dom.Element item, ListItemType type) {
  final list = item.parent;
  final parent = list?.parentNode;
  final tag = type == ListItemType.ordered ? 'ol' : 'ul';
  if (list == null || parent == null || list.localName == tag) return;
  final index = parent.nodes.indexOf(list);
  final after = list.clone(false);
  final following = list.nodes.skip(list.nodes.indexOf(item) + 1).toList();
  for (final child in following) {
    child.remove();
    after.nodes.add(child);
  }
  item.remove();
  final replacement = dom.Element.tag(tag)..nodes.add(item);
  parent.nodes.insert(index + 1, replacement);
  if (after.children.isNotEmpty) parent.nodes.insert(index + 2, after);
  if (list.children.isEmpty) list.remove();
}

/// Display retained span styles without introducing another HTML renderer for
/// editable text. The DOM envelope remains responsible for export.
TextStyle htmlInlineTextStyler(Set<Attribution> attributions, TextStyle base) {
  var result = defaultInlineTextStyler(attributions, base);
  for (final element
      in attributions.whereType<_HtmlInline>().firstOrNull?.wrappers ??
          <dom.Element>[]) {
    final declarations = <String, String>{};
    for (final declaration in (element.attributes['style'] ?? '').split(';')) {
      final colon = declaration.indexOf(':');
      if (colon > 0)
        declarations[declaration.substring(0, colon).trim().toLowerCase()] =
            declaration.substring(colon + 1).trim();
    }
    Color? color(String? value) {
      if (value == null) return null;
      try {
        return Color(css.Color.css(value).argbValue);
      } catch (_) {
        return null;
      }
    }

    final sizeValue = declarations['font-size'] ?? '';
    final dimension =
        RegExp(r'^(\d+(?:\.\d+)?)(px|pt|em|rem|%)$').firstMatch(sizeValue);
    final amount =
        dimension == null ? null : double.tryParse(dimension.group(1)!);
    final size = amount == null
        ? null
        : amount *
            switch (dimension!.group(2)) {
              'pt' => 4 / 3,
              'em' => result.fontSize ?? 16,
              'rem' => base.fontSize ?? 16,
              '%' => (result.fontSize ?? 16) / 100,
              _ => 1,
            };
    result = result.copyWith(
        color: color(declarations['color'] ?? element.attributes['color']),
        backgroundColor: color(declarations['background-color']),
        fontSize: size,
        fontFamily: declarations['font-family'] ?? element.attributes['face']);
  }
  return result;
}

class PreservedHtmlNode extends BlockNode {
  PreservedHtmlNode({required this.id, required this.html, super.metadata});
  @override
  final String id;
  final String html;
  @override
  bool hasEquivalentContent(DocumentNode other) =>
      other is PreservedHtmlNode && html == other.html;
  @override
  String? copyContent(NodeSelection selection) => html;
  @override
  DocumentNode copyAndReplaceMetadata(Map<String, dynamic> newMetadata) =>
      PreservedHtmlNode(id: id, html: html, metadata: newMetadata);
  @override
  DocumentNode copyWithAddedMetadata(Map<String, dynamic> newProperties) =>
      copyAndReplaceMetadata({...metadata, ...newProperties});
}

const _blockTags = {
  'p',
  'div',
  'h1',
  'h2',
  'h3',
  'h4',
  'h5',
  'h6',
  'pre',
  'blockquote',
  'li',
  'td',
  'th'
};
const _inlineTags = {
  'span',
  'a',
  'b',
  'strong',
  'i',
  'em',
  'u',
  's',
  'strike',
  'del',
  'sub',
  'sup',
  'code',
  'br',
  'font',
  'small',
  'mark',
  'abbr'
};
const _semantic = <String, Attribution>{
  'strong': boldAttribution,
  'b': boldAttribution,
  'em': italicsAttribution,
  'i': italicsAttribution,
  'u': underlineAttribution,
  's': strikethroughAttribution,
  'strike': strikethroughAttribution,
  'del': strikethroughAttribution,
  'code': codeAttribution,
};

bool _containsBlocksOrImages(dom.Element element) =>
    element.children.any((child) =>
        !_inlineTags.contains(child.localName) ||
        _containsBlocksOrImages(child));

dom.Node _body(dom.Node root) => root is dom.Document ? root.body! : root;

Attribution _blockAttribution(String tag) => switch (tag) {
      'h1' => header1Attribution,
      'h2' => header2Attribution,
      'h3' => header3Attribution,
      'h4' => header4Attribution,
      'h5' => header5Attribution,
      'h6' => header6Attribution,
      'blockquote' => blockquoteAttribution,
      'pre' => const NamedAttribution('pre'),
      _ => paragraphAttribution,
    };

String _paragraphTag(TextNode node) {
  final type = node.getMetadataValue('blockType');
  for (final tag in ['h1', 'h2', 'h3', 'h4', 'h5', 'h6', 'blockquote', 'pre']) {
    if (type == _blockAttribution(tag)) return tag;
  }
  return 'p';
}

String? _alignment(dom.Element element) {
  final css = RegExp(r'text-align\s*:\s*(left|center|right|justify)')
      .firstMatch(element.attributes['style'] ?? '')
      ?.group(1);
  return css ??
      RegExp(r'ql-align-(left|center|right|justify)')
          .firstMatch(element.attributes['class'] ?? '')
          ?.group(1);
}

ListItemType _listType(dom.Element element) =>
    element.attributes['data-list'] == 'bullet' ||
            element.parent?.localName == 'ul'
        ? ListItemType.unordered
        : ListItemType.ordered;
int _listIndent(dom.Element element) {
  final quill = int.tryParse(RegExp(r'ql-indent-(\d+)')
          .firstMatch(element.attributes['class'] ?? '')
          ?.group(1) ??
      '');
  if (quill != null) return quill;
  var depth = -1;
  for (dom.Element? parent = element.parent;
      parent != null;
      parent = parent.parent) {
    if (parent.localName == 'ul' || parent.localName == 'ol') depth++;
  }
  return depth.clamp(0, 20);
}

AttributedText _readInline(List<dom.Node> nodes) {
  final buffer = StringBuffer();
  final ranges = <(int, int, List<dom.Element>)>[];
  void visit(dom.Node node, List<dom.Element> wrappers) {
    if (node is dom.Text || node is dom.Element && node.localName == 'br') {
      final value = node is dom.Text ? node.data : '\n';
      final start = buffer.length;
      buffer.write(value);
      if (value.isNotEmpty) ranges.add((start, buffer.length - 1, wrappers));
    } else if (node is dom.Element) {
      for (final child in node.nodes) {
        visit(child, [...wrappers, node.clone(false)]);
      }
    }
  }

  for (final node in nodes) {
    visit(node, []);
  }
  final result = AttributedText(buffer.toString());
  for (final (start, end, wrappers) in ranges) {
    final range = SpanRange(start, end);
    if (wrappers.isNotEmpty)
      result.addAttribution(_HtmlInline(wrappers), range);
    for (final wrapper in wrappers) {
      final semantic = _semantic[wrapper.localName];
      if (semantic != null) result.addAttribution(semantic, range);
      if (wrapper.localName == 'a' && wrapper.attributes['href'] != null) {
        result.addAttribution(
            LinkAttribution(wrapper.attributes['href']!), range);
      }
    }
  }
  return result;
}

class _HtmlInline implements Attribution {
  _HtmlInline(this.wrappers);
  final List<dom.Element> wrappers;
  @override
  String get id => 'html-inline';
  String get signature => wrappers.map((e) => e.outerHtml).join();
  @override
  bool canMergeWith(Attribution other) =>
      other is _HtmlInline && signature == other.signature;
  @override
  bool operator ==(Object other) =>
      other is _HtmlInline && signature == other.signature;
  @override
  int get hashCode => signature.hashCode;
}

String _writeInline(AttributedText text, {bool preformatted = false}) {
  final result = StringBuffer();
  for (final span in text.computeAttributionSpans()) {
    final attributed = span.attributions;
    final envelope = attributed.whereType<_HtmlInline>().firstOrNull;
    final root = dom.DocumentFragment();
    dom.Node container = root;
    final represented = <Attribution>{};
    for (final source in envelope?.wrappers ?? <dom.Element>[]) {
      final semantic = _semantic[source.localName];
      if (semantic != null && !attributed.contains(semantic)) continue;
      if (source.localName == 'a' &&
          attributed.whereType<LinkAttribution>().isEmpty) continue;
      final wrapper = source.clone(false);
      if (source.localName == 'a')
        wrapper.attributes['href'] =
            attributed.whereType<LinkAttribution>().first.plainTextUri;
      container.nodes.add(wrapper);
      container = wrapper;
      if (semantic != null) represented.add(semantic);
    }
    for (final entry in {
      'strong': boldAttribution,
      'em': italicsAttribution,
      'u': underlineAttribution,
      's': strikethroughAttribution,
      'code': codeAttribution
    }.entries) {
      if (attributed.contains(entry.value) &&
          !represented.contains(entry.value)) {
        final wrapper = dom.Element.tag(entry.key);
        container.nodes.add(wrapper);
        container = wrapper;
      }
    }
    if (attributed.whereType<LinkAttribution>().isNotEmpty &&
        !(envelope?.wrappers.any((w) => w.localName == 'a') ?? false)) {
      final link = dom.Element.tag('a')
        ..attributes['href'] =
            attributed.whereType<LinkAttribution>().first.plainTextUri;
      container.nodes.add(link);
      container = link;
    }
    final value = text.toPlainText().substring(span.start, span.end + 1);
    if (preformatted) {
      container.nodes.add(dom.Text(value));
      result.write(root.outerHtml);
      continue;
    }
    final lines = value.split('\n');
    for (var i = 0; i < lines.length; i++) {
      if (i > 0) container.nodes.add(dom.Element.tag('br'));
      container.nodes.add(dom.Text(lines[i]));
    }
    result.write(root.outerHtml);
  }
  return result.toString();
}

DocumentNode _copyNode(DocumentNode node) {
  if (node is TextNode) return node.copyTextNodeWith(text: node.text.copy());
  if (node is ImageNode) return node.copy();
  return node.copyAndReplaceMetadata(Map.of(node.metadata));
}

bool _equivalent(DocumentNode a, DocumentNode b) =>
    a.runtimeType == b.runtimeType &&
    a.hasEquivalentContent(b) &&
    jsonEncode(a.metadata.map((k, v) => MapEntry(k, v.toString()))) ==
        jsonEncode(b.metadata.map((k, v) => MapEntry(k, v.toString())));
