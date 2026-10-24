/// Stable question keys are independent of their position and persisted step.
class OccasionSetupQuestion {
  final int step;
  final String key;
  final bool optional;
  const OccasionSetupQuestion(this.step, this.key, {this.optional = false});
}

class OccasionSetupStory {
  static const kinds = ['regular', 'concert', 'ball'];
  static String kind(Map data) =>
      data['eventKind'] as String? ??
      ((data['blueprintObjects'] as List? ?? []).isNotEmpty
          ? 'ball'
          : data['ticketDraft'] is Map
              ? 'concert'
              : 'regular');
  static bool tickets(Map data) => kind(data) != 'regular';
  static bool seats(Map data) => kind(data) == 'ball';
  static bool paid(Map data) {
    final form = data['formDraft'] as Map?;
    return ((form?['fields'] as List?) ?? []).whereType<Map>().any((field) {
      final type = field['product_type_data'] ?? field['product_type'];
      return type is Map &&
          (type['products'] as List? ?? []).whereType<Map>().any(
              (p) => p['is_hidden'] != true && (p['price'] as num? ?? 0) > 0);
    });
  }

  static void normalize(Map<String, dynamic> data, bool appSupported) {
    if (!data.containsKey('eventKind')) {
      data['eventKind'] = kind(data);
      data['eventKindNeedsConfirmation'] = true;
      data['reviewed'] = false;
      data['reviewConfirmed'] = false;
    }
    if (data['storyQuestion'] == 'start' || data['storyQuestion'] == 'end') {
      data['storyQuestion'] = 'dates';
    }
    if (data['storyQuestion'] == 'ticket') data['storyQuestion'] = 'appearance';
    final key = data['storyQuestion'];
    if (key != null &&
        key != 'source' &&
        !questions(appSupported, data: data).any((q) => q.key == key)) {
      data['storyQuestion'] = 'kind';
      data['step'] = 1;
      data['pathNotice'] = true;
    }
    if (data['formDraft'] is Map) {
      (data['formDraft'] as Map)['title'] = data['title'] ?? '';
    }
  }

  static List<OccasionSetupQuestion> questions(bool appSupported,
          {Map<String, dynamic> data = const {}, bool includeSource = false}) =>
      [
        if (includeSource)
          const OccasionSetupQuestion(0, 'source', optional: true),
        const OccasionSetupQuestion(1, 'name'),
        const OccasionSetupQuestion(1, 'dates'),
        const OccasionSetupQuestion(1, 'kind'),
        const OccasionSetupQuestion(2, 'appearance'),
        if (appSupported) const OccasionSetupQuestion(1, 'link'),
        if (appSupported) const OccasionSetupQuestion(2, 'content'),
        const OccasionSetupQuestion(3, 'form'),
        const OccasionSetupQuestion(3, 'saleTiming'),
        if (paid(data)) ...[
          OccasionSetupQuestion(appSupported ? 3 : 4, 'payments'),
          OccasionSetupQuestion(appSupported ? 3 : 4, 'paymentTiming'),
        ],
        const OccasionSetupQuestion(3, 'communication'),
        if (seats(data))
          OccasionSetupQuestion(appSupported ? 4 : 6, 'blueprint'),
        const OccasionSetupQuestion(5, 'verification', optional: true),
        const OccasionSetupQuestion(5, 'review'),
      ];

  static int index(Map<String, dynamic> data, bool appSupported,
      {bool includeSource = false}) {
    final pages =
        questions(appSupported, data: data, includeSource: includeSource);
    final exact = pages.indexWhere(
        (p) => p.step == data['step'] && p.key == data['storyQuestion']);
    if (exact >= 0) return exact;
    if (data['storyQuestion'] != null &&
        !pages.any((q) => q.key == data['storyQuestion'])) {
      return pages.indexWhere((q) => q.key == 'kind');
    }
    if (data['step'] == 5) return pages.length - 1;
    final first = pages.indexWhere((p) => p.step == data['step']);
    return first < 0 ? 0 : first;
  }
}
