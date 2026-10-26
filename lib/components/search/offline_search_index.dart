import 'package:fstapp/components/html/html_helper.dart';
import 'package:fstapp/components/search/search_result_model.dart';

class OfflineSearchDocument {
  final String entityType;
  final int entityId;
  final String? title;
  final String? snippet;
  final DateTime? startTime;
  final int? parentId;
  final String searchText;

  const OfflineSearchDocument({
    required this.entityType,
    required this.entityId,
    required this.searchText,
    this.title,
    this.snippet,
    this.startTime,
    this.parentId,
  });
}

class OfflineSearchIndexCache {
  final Future<List<OfflineSearchDocument>> Function() loadDocuments;
  final int Function() readEpoch;
  final int limit;

  List<_IndexedDocument> _index = const [];
  int? _builtEpoch;
  Future<void>? _rebuildInFlight;

  OfflineSearchIndexCache({
    required this.loadDocuments,
    required this.readEpoch,
    this.limit = 50,
  });

  Future<List<SearchResultModel>> search(String query) async {
    final normalized = normalizeSearchText(query.trim());
    if (normalized.isEmpty) return [];
    await _ensureCurrent();
    final tokens = normalized
        .split(RegExp(r'\s+'))
        .where((token) => token.isNotEmpty)
        .toList(growable: false);
    if (tokens.isEmpty) return [];

    return _index
        .where((document) =>
            tokens.every((token) => document.normalized.contains(token)))
        .map((document) => document.toResult())
        .take(limit)
        .toList(growable: false);
  }

  Future<void> rebuild() async {
    _builtEpoch = null;
    await _ensureCurrent();
  }

  Future<void> _ensureCurrent() async {
    while (_builtEpoch != readEpoch()) {
      final pending = _rebuildInFlight;
      if (pending != null) {
        await pending;
        continue;
      }
      final targetEpoch = readEpoch();
      final rebuild = _load(targetEpoch);
      _rebuildInFlight = rebuild;
      try {
        await rebuild;
      } finally {
        if (identical(_rebuildInFlight, rebuild)) {
          _rebuildInFlight = null;
        }
      }
    }
  }

  Future<void> _load(int targetEpoch) async {
    final documents = await loadDocuments();
    _index = documents
        .map((document) => _IndexedDocument(
              source: document,
              normalized: normalizeSearchText(document.searchText),
            ))
        .toList(growable: false);
    _builtEpoch = targetEpoch;
  }
}

class _IndexedDocument {
  final OfflineSearchDocument source;
  final String normalized;

  const _IndexedDocument({required this.source, required this.normalized});

  SearchResultModel toResult() => SearchResultModel(
        entityType: source.entityType,
        entityId: source.entityId,
        title: source.title,
        snippet: source.snippet == null
            ? null
            : HtmlHelper.htmlToSnippet(source.snippet),
        startTime: source.startTime,
        parentId: source.parentId,
        rank: 1,
      );
}

String normalizeSearchText(String input) {
  final lower = input.toLowerCase();
  final output = StringBuffer();
  for (final character in lower.runes) {
    output.write(_diacritics[character] ?? String.fromCharCode(character));
  }
  return output.toString();
}

const Map<int, String> _diacritics = {
  0x00E1: 'a',
  0x010D: 'c',
  0x010F: 'd',
  0x00E9: 'e',
  0x011B: 'e',
  0x00ED: 'i',
  0x0148: 'n',
  0x00F3: 'o',
  0x0159: 'r',
  0x0161: 's',
  0x0165: 't',
  0x00FA: 'u',
  0x016F: 'u',
  0x00FD: 'y',
  0x017E: 'z',
  0x00E4: 'a',
  0x00F6: 'o',
  0x00FC: 'u',
  0x00DF: 'ss',
  0x0142: 'l',
  0x0144: 'n',
  0x015B: 's',
  0x017A: 'z',
  0x017C: 'z',
  0x0107: 'c',
  0x00E0: 'a',
  0x00E8: 'e',
  0x00EA: 'e',
  0x00F4: 'o',
  0x00E2: 'a',
};
