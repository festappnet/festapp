/// Questions are stored inside the existing stable draft steps. Optional
/// questions never participate in the event's completion requirements.
class OccasionSetupQuestion {
  final int step;
  final String key;
  final bool optional;
  const OccasionSetupQuestion(this.step, this.key, {this.optional = false});
}

class OccasionSetupStory {
  static bool formEnabled(Map<String, dynamic> data) =>
      data['formEnabled'] != false;

  static Iterable<Map> _visibleFields(Map<String, dynamic> data) {
    final form = data['formDraft'];
    if (!formEnabled(data) || form is! Map) return const [];
    return (form['fields'] as List? ?? []).whereType<Map>().where(
          (field) => field['is_hidden'] != true,
        );
  }

  static bool hasTickets(Map<String, dynamic> data) =>
      _visibleFields(data).any((field) => field['type'] == 'ticket');

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

  static bool paymentAccountConfirmed(Map<String, dynamic> data) =>
      data['bankAccountId'] is int &&
      (data['bankAccountId'] as int) > 0 &&
      data['bankAccountConfirmed'] == true;

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
      final targets =
          (wave['targets'] as List? ?? []).whereType<Map>().toList();
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
  ) =>
      questions(appSupported, data: data)
          .where((question) => !question.optional)
          .map((question) => question.step)
          .toSet();

  static List<OccasionSetupQuestion> questions(
    bool appSupported, {
    Map<String, dynamic>? data,
    bool organizationVerified = false,
  }) {
    final form = data == null || formEnabled(data);
    final paid = data == null || hasPaidProducts(data);
    final tickets = data == null || hasTickets(data);
    return [
      const OccasionSetupQuestion(0, 'source'),
      const OccasionSetupQuestion(1, 'name'),
      const OccasionSetupQuestion(1, 'dates'),
      const OccasionSetupQuestion(1, 'presentation'),
      if (appSupported) const OccasionSetupQuestion(1, 'link'),
      if (appSupported) const OccasionSetupQuestion(2, 'content'),
      if (form) const OccasionSetupQuestion(3, 'form'),
      if (paid) const OccasionSetupQuestion(3, 'pricing'),
      if (paid) OccasionSetupQuestion(appSupported ? 3 : 4, 'payments'),
      if (paid) OccasionSetupQuestion(appSupported ? 3 : 4, 'paymentTiming'),
      if (form) const OccasionSetupQuestion(3, 'communication'),
      if (form) OccasionSetupQuestion(appSupported ? 4 : 6, 'blueprint'),
      if (!appSupported) ...[
        if (tickets) const OccasionSetupQuestion(2, 'ticket'),
        if (tickets && data?['configureScanning'] == true)
          const OccasionSetupQuestion(2, 'scanner', optional: true),
      ],
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
    );
    final savedKey = data['storyQuestion'];
    final key = savedKey == 'start' || savedKey == 'end' ? 'dates' : savedKey;
    final exact = pages.indexWhere(
      (p) => p.step == data['step'] && p.key == key,
    );
    if (exact >= 0) return exact;
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
