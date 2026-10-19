import 'package:flutter/material.dart';
import 'package:super_editor/super_editor.dart';

/// Domain-neutral presentation boundary. Persisted identity is always [code].
class TemplateTokenPlaceholder {
  const TemplateTokenPlaceholder(this.code);
  final String code;
  String get source => '{{ $code }}'.replaceAll(' ', '');
  @override
  bool operator ==(Object other) =>
      other is TemplateTokenPlaceholder && code == other.code;
  @override
  int get hashCode => code.hashCode;
}

class TemplateAuthoringEntry {
  const TemplateAuthoringEntry(
      {required this.code,
      required this.label,
      this.example = '',
      this.description = '',
      this.rich = false,
      this.repeatable = true,
      this.block = false,
      this.url = false});
  final String code;
  final String label;
  final String example;
  final String description;
  final bool rich;
  final bool repeatable;
  final bool block;
  final bool url;
}

abstract class TemplateAuthoringProvider {
  Set<String> get codes;
  bool get singleLine => false;
  TextStyle? get textStyle => null;
  String get helper;
  String get insertLabel;
  String get emptyLabel;
  String get usedLabel;
  String get sampleLabel;
  String get tokenLabel;
  String get unsupportedLabel => '';
  String get recommendedLabel => insertLabel;
  String get usedBlocksLabel => usedLabel;
  String get uniqueUsedLabel => usedLabel;
  bool supports(String code) =>
      search('', const {}).any((entry) => entry.code == code);
  TemplateAuthoringEntry? entry(String code);
  List<TemplateAuthoringEntry> search(String query, Map<String, int> usage);
  bool canTrigger(String text, int offset,
      {bool inLink = false, bool inCode = false, bool composing = false});
  bool canInsert(String text, int offset,
      {bool inLink = false, bool inCode = false, bool composing = false});
  Widget? preview(BuildContext context, String code) => null;
  Widget? footer(BuildContext context) => null;
  void selectionChanged() {}
}

AttributedText tokenizeTemplateText(AttributedText source, Set<String> codes) {
  var result = source.copy();
  final matches = RegExp(r'\{\{([A-Za-z_][A-Za-z0-9_]*)\}\}')
      .allMatches(source.toPlainText())
      .toList();
  for (final match in matches.reversed) {
    if (!codes.contains(match.group(1))) continue;
    final token = AttributedText(
        '', null, {0: TemplateTokenPlaceholder(match.group(1)!)});
    for (final attribution in source.getAllAttributionsAt(match.start)) {
      token.addAttribution(attribution, const SpanRange(0, 0));
    }
    result = result
        .copyText(0, match.start)
        .copyAndAppend(token)
        .copyAndAppend(result.copyText(match.end));
  }
  return result;
}

String templatePlainText(AttributedText text, {int start = 0, int? end}) {
  final buffer = StringBuffer();
  for (var i = start; i < (end ?? text.length); i++) {
    final value = text[i];
    buffer.write(value is TemplateTokenPlaceholder ? value.source : value);
  }
  return buffer.toString();
}

class TemplateTokenBlock extends BlockNode {
  TemplateTokenBlock({required this.id, required this.code, super.metadata});
  @override
  final String id;
  final String code;
  @override
  bool hasEquivalentContent(DocumentNode other) =>
      other is TemplateTokenBlock && other.code == code;
  @override
  String copyContent(NodeSelection selection) =>
      TemplateTokenPlaceholder(code).source;
  @override
  DocumentNode copyAndReplaceMetadata(Map<String, dynamic> newMetadata) =>
      TemplateTokenBlock(id: id, code: code, metadata: newMetadata);
  @override
  DocumentNode copyWithAddedMetadata(Map<String, dynamic> newProperties) =>
      copyAndReplaceMetadata({...metadata, ...newProperties});
}
