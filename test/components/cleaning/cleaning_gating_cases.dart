import 'package:flutter_test/flutter_test.dart';
import 'package:fstapp/components/occasion/occasion_link_model.dart';
import 'package:fstapp/components/users/occasion_user_model.dart';
import 'package:fstapp/data_services/rights_service.dart';

/// Gating unit tests for the Cleaning service.
///
/// [RightsService.isCleaningCrew] is the single predicate that gates every
/// crew-only piece of UI on the Cleaning page: the "Current / History" tabs,
/// the report history + .txt export, the "block reporter" overflow action, the
/// "Cleaned" button and the notification opt-out. Only the per-occasion
/// `is_cleaning_crew` flag grants it; a plain participant — AND an editor/admin
/// who is not on the crew — must get `false` (they see only the simple report
/// view, since only actual crew receive the report notifications).
///
/// This mirrors the pure-predicate style of counseling_gating_test.dart — it
/// drives RightsService via its occasionLinkModel notifier, no Supabase needed.
void main() {
  void setContext({
    bool? isCleaningCrew,
    bool? isEditor,
    bool isAdmin = false,
    bool hasOccasionUser = true,
  }) {
    RightsService.occasionLinkModelNotifier.value = OccasionLinkModel(
      isAdmin: isAdmin,
      occasionUser: hasOccasionUser
          ? OccasionUserModel(
              isCleaningCrew: isCleaningCrew,
              isEditor: isEditor,
            )
          : null,
    );
  }

  tearDown(() {
    // Avoid leaking the static context into other tests.
    RightsService.occasionLinkModelNotifier.value = null;
  });

  group('RightsService.isCleaningCrew gating', () {
    test('no occasion context → not crew', () {
      RightsService.occasionLinkModelNotifier.value = null;
      expect(RightsService.isCleaningCrew(), isFalse);
    });

    test('occasion user missing → not crew', () {
      setContext(hasOccasionUser: false);
      expect(RightsService.isCleaningCrew(), isFalse);
    });

    test('plain participant (no flags) → not crew', () {
      setContext(isCleaningCrew: false, isEditor: false);
      expect(RightsService.isCleaningCrew(), isFalse);
    });

    test('is_cleaning_crew flag → crew', () {
      setContext(isCleaningCrew: true, isEditor: false);
      expect(RightsService.isCleaningCrew(), isTrue);
    });

    test('editor (without the crew flag) → NOT crew', () {
      setContext(isCleaningCrew: false, isEditor: true);
      expect(RightsService.isCleaningCrew(), isFalse);
    });

    test('admin (without the crew flag) → NOT crew', () {
      setContext(isCleaningCrew: false, isEditor: false, isAdmin: true);
      expect(RightsService.isCleaningCrew(), isFalse);
    });
  });
}
