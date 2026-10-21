import 'occasion_setup_result.dart';
import 'package:fstapp/app_config.dart';
import 'package:fstapp/components/forms/views/form_public_link.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:uuid/uuid.dart';
import 'occasion_setup_story.dart';

class OccasionSetupDraft {
  final String id;
  final int unit;
  final int revision;
  final int step;
  final Map<String, dynamic> data;

  OccasionSetupDraft.fromJson(Map<String, dynamic> json)
      : id = json['id'] as String,
        unit = (json['unit'] as num).toInt(),
        revision = (json['revision'] as num).toInt(),
        step = (json['current_step'] as num).toInt(),
        data = Map<String, dynamic>.from(json['data'] as Map);

  // Keep persisted step IDs stable across tenant capabilities.
  static List<int> get supportedSteps =>
      AppConfig.isAppSupported ? [0, 1, 2, 3, 4, 5] : [0, 1, 3, 6, 4, 2, 5];

  static int completedCount(Map<String, dynamic> data) => (data['completed']
              as List? ??
          [])
      .whereType<int>()
      .toSet()
      .intersection(
          OccasionSetupStory.applicableSteps(data, AppConfig.isAppSupported))
      .length;

  bool get isFinalized => data.containsKey('finalizedOccasion');

  String get title => data['title'] as String? ?? '';
  int get progress => data['completed'] is List
      ? ((completedCount(data) /
                  OccasionSetupStory.applicableSteps(
                          data, AppConfig.isAppSupported)
                      .length) *
              100)
          .round()
          .clamp(0, 100)
      : (basicsReady ? 20 : 0);

  bool get basicsReady =>
      title.trim().isNotEmpty &&
      isValidPublicSlug(data['link'] as String? ?? '', allowEmpty: true) &&
      DateTime.tryParse(
              (data['start'] ?? data['start_time']) as String? ?? '') !=
          null &&
      DateTime.tryParse((data['end'] ?? data['end_time']) as String? ?? '') !=
          null &&
      !DateTime.parse(data['end'] ?? data['end_time'])
          .isBefore(DateTime.parse(data['start'] ?? data['start_time']));
}

class OccasionSetupDrafts {
  final SupabaseClient client;
  OccasionSetupDrafts(this.client);

  Future<List<OccasionSetupDraft>> list(int unit) async {
    final rows =
        await client.rpc('get_occasion_setup_drafts', params: {'p_unit': unit});
    return (rows as List)
        .map((row) =>
            OccasionSetupDraft.fromJson(Map<String, dynamic>.from(row)))
        .where((draft) => !draft.isFinalized)
        .toList();
  }

  Future<OccasionSetupDraft> get(String id) async =>
      OccasionSetupDraft.fromJson(Map<String, dynamic>.from(
          await client.rpc('get_occasion_setup_draft', params: {'p_id': id})));

  Future<OccasionSetupDraft> create(int unit, String id) async =>
      OccasionSetupDraft.fromJson(Map<String, dynamic>.from(await client.rpc(
          'create_occasion_setup_draft',
          params: {'p_id': id, 'p_unit': unit})));

  Future<OccasionSetupDraft> initializeDefaults(
          OccasionSetupDraft draft) async =>
      OccasionSetupDraft.fromJson(Map<String, dynamic>.from(await client.rpc(
          'initialize_occasion_setup_draft_defaults',
          params: {'p_id': draft.id, 'p_expected_revision': draft.revision})));

  static String newId() => const Uuid().v4();

  Future<OccasionSetupDraft> save(OccasionSetupDraft draft,
          Map<String, dynamic> data, int step) async =>
      OccasionSetupDraft.fromJson(Map<String, dynamic>.from(
          await client.rpc('save_occasion_setup_draft', params: {
        'p_id': draft.id,
        'p_expected_revision': draft.revision,
        'p_data': data,
        'p_step': step
      })));

  Future<OccasionSetupResult> finalize(
      OccasionSetupDraft draft, String commandId) async {
    final response = Map<String, dynamic>.from(
        await client.rpc('finalize_occasion_setup_draft', params: {
      'p_id': draft.id,
      'p_expected_revision': draft.revision,
      'p_command_id': commandId,
    }));
    final data = response['data'] as Map;
    return OccasionSetupResult(
        occasionId: data['occasionId'] as int,
        unit: draft.unit,
        link: data['link'] as String,
        title: draft.title,
        formLink: data['formLink'] as String?,
        saleMode: data['saleMode'] as String? ?? 'preparation');
  }

  Future<Map<String, dynamic>> blueprintResources(
      OccasionSetupDraft draft) async {
    final response = Map<String, dynamic>.from(await client.rpc(
        'get_occasion_setup_blueprint_resources',
        params: {'p_draft': draft.id}));
    return Map<String, dynamic>.from(response['resources'] as Map);
  }

  Future<void> delete(OccasionSetupDraft draft) async {
    await client.rpc('delete_occasion_setup_draft', params: {
      'p_id': draft.id,
      'p_unit': draft.unit,
      'p_expected_revision': draft.revision
    });
  }
}
