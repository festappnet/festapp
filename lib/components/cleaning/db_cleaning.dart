import 'package:fstapp/components/cleaning/cleaning_commands.dart';
import 'package:fstapp/components/cleaning/models/cleaning_place_status.dart';
import 'package:fstapp/components/cleaning/models/cleaning_report.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Data access for the Cleaning service. Backed exclusively by the SECURITY
/// DEFINER RPCs report_cleaning_issue / get_cleaning_status /
/// get_cleaning_reports / resolve_cleaning_place — participants and crew have
/// no direct table access, so there are no .from().insert calls here.
/// Online-only (no offline caching): the crew needs live data.
class DbCleaning {
  static final _supabase = Supabase.instance.client;
  static CleaningCommands get _commands => SupabaseCleaningCommands(_supabase);

  /// Reports a problem on a toilet. Returns the parsed result (with the
  /// duplicate flag). Throws [CleaningException] on any non-200 envelope.
  static Future<CleaningReportResult> reportIssue({
    required int placeId,
    required String problemType,
    String? note,
  }) async {
    final result = await _commands.report(
      placeId: placeId,
      problemType: problemType,
      note: note,
    );
    _ensureCommandOk(result);
    return CleaningReportResult(duplicate: result.data['duplicate'] == true);
  }

  /// Public per-toilet status (drives the tile grid and map colors). Also carries
  /// is_blocked for the caller so a banned reporter's UI can grey the report
  /// action out without an extra round-trip.
  static Future<CleaningStatusResult> getStatus(int occasionId) async {
    final res = await _supabase.rpc('get_cleaning_status', params: {
      'oc': occasionId,
    });
    _ensureOk(res);
    final places = ((res['data'] as List?) ?? const [])
        .map((e) =>
            CleaningPlaceStatus.fromJson((e as Map).cast<String, dynamic>()))
        .toList();
    return CleaningStatusResult(
      places: places,
      isBlocked: res is Map && res['is_blocked'] == true,
      notificationsMuted: res is Map && res['notifications_muted'] == true,
    );
  }

  /// Mutes/unmutes cleaning push notifications for the current user on the
  /// occasion (self-service opt-out). Throws [CleaningException] on a non-200
  /// envelope.
  static Future<void> setNotificationsMuted({
    required int occasionId,
    required bool muted,
  }) async {
    final result = await _commands.setNotificationsMuted(occasionId, muted);
    _ensureCommandOk(result);
    return;
  }

  /// Crew blocks (or editor unblocks) a repeat offender on the occasion.
  /// Throws [CleaningException] on a non-200 envelope (403 when the caller lacks
  /// the rights: crew may block, only editors may unblock).
  static Future<void> setReporterBlocked({
    required int occasionId,
    required String userId,
    required bool blocked,
  }) async {
    final result =
        await _commands.setReporterBlocked(occasionId, userId, blocked);
    _ensureCommandOk(result);
    return;
  }

  /// Crew-only detailed reports (notes, times, reporter).
  static Future<List<CleaningReport>> getReports(
    int occasionId, {
    bool includeResolved = false,
  }) async {
    final res = await _supabase.rpc('get_cleaning_reports', params: {
      'oc': occasionId,
      'p_include_resolved': includeResolved,
    });
    _ensureOk(res);
    return ((res['data'] as List?) ?? const [])
        .map((e) => CleaningReport.fromJson((e as Map).cast<String, dynamic>()))
        .toList();
  }

  /// Crew-only: resolve every open report of a toilet. Returns the count closed.
  static Future<int> resolvePlace(int placeId) async {
    final result = await _commands.resolve(placeId);
    _ensureCommandOk(result);
    return (result.data['resolved'] as num?)?.toInt() ?? 0;
  }

  static void _ensureOk(dynamic res) {
    if (res is Map && res['code'] != null && res['code'] != 200) {
      throw CleaningException(
          (res['code'] as num).toInt(), res['message'] as String?);
    }
  }

  static void _ensureCommandOk(CleaningCommandResult result) {
    if (result.status == 'rejected' || result.status == 'conflict') {
      throw CleaningException(result.code, result.data['message'] as String?);
    }
  }
}

class CleaningReportResult {
  final bool duplicate;
  CleaningReportResult({required this.duplicate});
}

/// Result of get_cleaning_status: the per-toilet statuses plus whether the
/// current caller is blocked from reporting on this occasion.
class CleaningStatusResult {
  final List<CleaningPlaceStatus> places;
  final bool isBlocked;

  /// Whether the current user has muted cleaning push notifications for
  /// themselves on this occasion (crew self-service opt-out).
  final bool notificationsMuted;

  CleaningStatusResult({
    required this.places,
    required this.isBlocked,
    this.notificationsMuted = false,
  });
}

/// Carries the RPC error code so the UI can show the matching message
/// (429 rate-limited, etc.).
class CleaningException implements Exception {
  final int code;
  final String? message;
  CleaningException(this.code, this.message);
}
