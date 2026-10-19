/// Questions are stored inside the existing stable draft steps. Optional
/// questions never participate in the event's completion requirements.
class OccasionSetupQuestion {
  final int step;
  final String key;
  final bool optional;
  const OccasionSetupQuestion(this.step, this.key, {this.optional = false});
}

class OccasionSetupStory {
  static List<OccasionSetupQuestion> questions(bool appSupported) => [
        const OccasionSetupQuestion(0, 'source'),
        const OccasionSetupQuestion(1, 'name'),
        const OccasionSetupQuestion(1, 'start'),
        const OccasionSetupQuestion(1, 'end'),
        if (appSupported) const OccasionSetupQuestion(1, 'link'),
        if (appSupported) const OccasionSetupQuestion(2, 'content'),
        const OccasionSetupQuestion(3, 'form'),
        OccasionSetupQuestion(appSupported ? 4 : 6, 'blueprint'),
        if (!appSupported) ...[
          const OccasionSetupQuestion(4, 'payments'),
          const OccasionSetupQuestion(2, 'ticket'),
        ],
        const OccasionSetupQuestion(5, 'verification', optional: true),
        const OccasionSetupQuestion(5, 'review'),
      ];

  static int index(Map<String, dynamic> data, bool appSupported) {
    final pages = questions(appSupported);
    final exact = pages.indexWhere(
        (p) => p.step == data['step'] && p.key == data['storyQuestion']);
    if (exact >= 0) return exact;
    // Older drafts at review should resume at review, not optional verification.
    if (data['step'] == 5) return pages.length - 1;
    final first = pages.indexWhere((p) => p.step == data['step']);
    return first < 0 ? 0 : first;
  }
}
