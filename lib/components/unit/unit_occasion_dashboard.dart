import '../occasion/occasion_model.dart';
import '../occasion/setup/occasion_setup_draft.dart';
import '../occasion/demo/demo_catalog.dart';
import 'app_landing.dart';

/// One coherent response for the whole occasion screen. Drafts remain private
/// to the permission-checked unit context; no card starts its own request.
class UnitOccasionDashboard {
  final int unitId;
  final List<OccasionModel> occasions;
  final List<OccasionSetupDraft> drafts;
  final AppLanding? landing;
  final DemoCatalog demos;
  UnitOccasionDashboard.fromJson(Map<String, dynamic> json)
      : unitId = (json['unit_id'] as num).toInt(),
        occasions = (json['occasions'] as List)
            .map((e) => OccasionModel.fromJson(Map<String, dynamic>.from(e)))
            .toList(),
        drafts = (json['drafts'] as List)
            .map((e) =>
                OccasionSetupDraft.fromJson(Map<String, dynamic>.from(e)))
            .toList(),
        landing = json['app_landing'] == null
            ? null
            : AppLanding.fromJson(
                Map<String, dynamic>.from(json['app_landing'])),
        demos = DemoCatalog.fromJson(
            Map<String, dynamic>.from(json['demo_catalog']));
}
