/// Questions are stored inside the existing stable draft steps. Optional
/// questions never participate in the event's completion requirements.
class OccasionSetupQuestion {
  final int step;
  final String key;
  final bool optional;
  const OccasionSetupQuestion(this.step, this.key, {this.optional = false});
}

class OccasionSetupStory {
  static const kinds = ['regular', 'concert', 'ball'];
  static String kind(Map<String, dynamic> data) =>
      data['eventKind'] as String? ??
      ((data['blueprintLayoutDraft'] is Map)
          ? 'ball'
          : hasTickets(data)
          ? 'concert'
          : 'regular');
  static bool seats(Map<String, dynamic> data) => kind(data) == 'ball';
  static void normalize(Map<String, dynamic> data, bool appSupported) {
    if (data['eventKind'] == null) {
      data['eventKind'] = kind(data);
      data['eventKindNeedsConfirmation'] = true;
      data['reviewed'] = false;
      data['reviewConfirmed'] = false;
    }
    if (data['storyQuestion'] == null && data['step'] == 0) {
      data['storyQuestion'] = data['sourceId'] != null ? 'source' : 'name';
      data['step'] = data['sourceId'] != null ? 0 : 1;
    }
    if (data['eventKind'] != null) data['formEnabled'] = true;
    if (data['storyQuestion'] == 'ticket') {
      data['storyQuestion'] = 'appearance';
      data['step'] = 2;
    }
    if (data['storyQuestion'] == 'start' || data['storyQuestion'] == 'end')
      data['storyQuestion'] = 'dates';
    final key = data['storyQuestion'];
    if (key != null &&
        key != 'source' &&
        !questions(appSupported, data: data).any((q) => q.key == key)) {
      data['storyQuestion'] = 'kind';
      data['step'] = 1;
      data['pathNotice'] = true;
    }
    if (data['formDraft'] is Map)
      (data['formDraft'] as Map)['title'] = data['title'] ?? '';
  }

  static bool formEnabled(Map<String, dynamic> data) =>
      data['formEnabled'] != false;

  static Iterable<Map> _visibleFields(Map<String, dynamic> data) {
    final form = data['formDraft'];
    if (!formEnabled(data) || form is! Map) return const [];
    return (form['fields'] as List? ?? []).whereType<Map>().where(
      (field) => field['is_hidden'] != true &&
          !(data['eventKind'] == 'regular' && (field['type'] == 'ticket' || field['type'] == 'spot')) &&
          !(data['eventKind'] == 'concert' && field['type'] == 'spot'),
    );
  }

  static bool hasTickets(Map<String, dynamic> data) => data['eventKind'] != null
      ? data['eventKind'] != 'regular'
      : _visibleFields(data).any((field) => field['type'] == 'ticket');

  static bool hasPaidProducts(Map<String, dynamic> data) =>
      _visibleFields(data).any((field) {
        final type = field['product_type_data'];
        if (type is! Map) return false;
        return (type['products'] as List? ?? []).whereType<Map>().any(
          (product) =>
              product['is_hidden'] != true &&
              (num.tryParse('${product['price']}') ?? 0) > 0,
        );
      });

  static Set<String> paymentCurrencies(Map<String, dynamic> data) {
    final currencies = <String>{};
    for (final field in _visibleFields(data)) {
      final type = field['product_type_data'];
      if (type is! Map) continue;
      for (final product
          in (type['products'] as List? ?? []).whereType<Map>()) {
        if (product['is_hidden'] != true &&
            (num.tryParse('${product['price']}') ?? 0) > 0) {
          currencies.add(
            (product['currency_code'] as String? ?? 'CZK').toUpperCase(),
          );
        }
      }
    }
    return currencies;
  }

  static bool paymentAccountReady(Map<String, dynamic> data) =>
      data['bankAccountId'] is int &&
      (data['bankAccountId'] as int) > 0 &&
      (data['bankAccountFingerprint'] as String? ?? '').isNotEmpty;

  /// Validate only active price scheduling. Dormant choices survive backtracking
  /// without blocking a free event or a disabled form.
  static Set<String> pricingIssueKeys(Map<String, dynamic> data, DateTime now) {
    if (data['priceWavesEnabled'] != true || !hasPaidProducts(data)) return {};
    final waves = (data['priceWaves'] as List? ?? []).whereType<Map>().toList();
    if (waves.isEmpty) return {'pricingIncomplete'};
    final form = data['formDraft'] as Map;
    final products = <Object?>{};
    for (final field in (form['fields'] as List? ?? []).whereType<Map>()) {
      final type = field['product_type_data'];
      if (type is Map) {
        for (final product
            in (type['products'] as List? ?? []).whereType<Map>()) {
          products.add(product['id']);
        }
      }
    }
    final issues = <String>{};
    for (final wave in waves) {
      final time = DateTime.tryParse(wave['change_time'] as String? ?? '');
      if (time == null || !time.isAfter(now)) issues.add('pricingExpired');
      final targets = (wave['targets'] as List? ?? [])
          .whereType<Map>()
          .toList();
      if (targets.isEmpty) issues.add('pricingIncomplete');
      if (targets.any(
        (target) =>
            target['product'] == null || !products.contains(target['product']),
      )) {
        issues.add('pricingMissingProduct');
      }
    }
    return issues;
  }

  static Set<int> applicableSteps(
    Map<String, dynamic> data,
    bool appSupported,
  ) => questions(appSupported, data: data)
      .where((question) => !question.optional)
      .map((question) => question.step)
      .toSet();

  static List<OccasionSetupQuestion> questions(
    bool appSupported, {
    Map<String, dynamic>? data,
    bool organizationVerified = false,
    bool includeSource = false,
  }) {
    final form = data == null || formEnabled(data);
    final paid = data == null || hasPaidProducts(data);

    return [
      if (includeSource)
        const OccasionSetupQuestion(0, 'source', optional: true),
      const OccasionSetupQuestion(1, 'name'),
      const OccasionSetupQuestion(1, 'dates'),
      const OccasionSetupQuestion(1, 'kind'),
      const OccasionSetupQuestion(2, 'appearance'),
      if (appSupported) const OccasionSetupQuestion(1, 'presentation'),
      if (appSupported) const OccasionSetupQuestion(1, 'link'),
      if (appSupported) const OccasionSetupQuestion(2, 'content'),
      if (form) const OccasionSetupQuestion(3, 'form'),
      if (form) const OccasionSetupQuestion(3, 'saleTiming'),
      if (paid) const OccasionSetupQuestion(3, 'pricing'),
      if (paid) OccasionSetupQuestion(appSupported ? 3 : 4, 'payments'),
      if (paid) OccasionSetupQuestion(appSupported ? 3 : 4, 'paymentTiming'),
      if (form) const OccasionSetupQuestion(3, 'communication'),
      if (form && (data == null || seats(data)))
        OccasionSetupQuestion(appSupported ? 4 : 6, 'blueprint'),

      const OccasionSetupQuestion(5, 'team', optional: true),
      if (!organizationVerified)
        const OccasionSetupQuestion(5, 'verification', optional: true),
      const OccasionSetupQuestion(1, 'promotion'),
      const OccasionSetupQuestion(5, 'review'),
    ];
  }

  static bool completesRequiredStep(
    List<OccasionSetupQuestion> pages,
    int index,
  ) {
    final current = pages[index];
    if (current.optional) return false;
    return !pages
        .skip(index + 1)
        .any((next) => !next.optional && next.step == current.step);
  }

  static int index(
    Map<String, dynamic> data,
    bool appSupported, {
    bool organizationVerified = false,
    bool includeSource = false,
  }) {
    // Sparse historical position records have no form context. Full drafts
    // always carry formEnabled/formDraft and use the dependent journey.
    final context =
        data.containsKey('formEnabled') || data.containsKey('formDraft')
        ? data
        : null;
    final pages = questions(
      appSupported,
      data: context,
      organizationVerified: organizationVerified,
      includeSource: includeSource,
    );
    final savedKey = switch (data['storyQuestion']) {
      'presentation' when !appSupported => 'form',
      'scanner' => 'team',
      final value => value,
    };
    final key = savedKey == 'start' || savedKey == 'end' ? 'dates' : savedKey;
    final exact = pages.indexWhere(
      (p) =>
          p.key == key &&
          (p.step == data['step'] ||
              data['storyQuestion'] == 'scanner' ||
              data['storyQuestion'] == 'presentation'),
    );
    if (exact >= 0) return exact;
    if (key == 'verification' && organizationVerified) return pages.length - 1;
    if (key != null && key != 'source' && !pages.any((q) => q.key == key))
      return pages.indexWhere((q) => q.key == 'kind');
    if (data['step'] == 5) return pages.length - 1;
    final first = pages.indexWhere((p) => p.step == data['step']);
    if (first >= 0) return first;
    if (key == 'scanner') {
      final verification = pages.indexWhere((p) => p.key == 'verification');
      return verification >= 0 ? verification : pages.length - 1;
    }
    // A now-inapplicable saved question resumes at the next applicable one.
    final all = questions(appSupported);
    final previous = all.indexWhere((p) => p.key == key);
    for (final candidate in all.skip(previous < 0 ? 0 : previous + 1)) {
      final next = pages.indexWhere((p) => p.key == candidate.key);
      if (next >= 0) return next;
    }
    return pages.length - 1;
  }
}
