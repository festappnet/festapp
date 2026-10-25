import 'package:material_ui/material_ui.dart';
import 'package:fstapp/components/event_feedback/event_feedback_strings.dart';
import 'package:fstapp/components/single_data_grid/pluto_abstract.dart';
import 'package:trina_grid/trina_grid.dart';

/// Read-only feedback row adapter for the shared admin data grid.
class EventFeedbackAdminRow extends ITrinaRowModel {
  static const feedbackIdColumn = 'feedback_id';
  static const eventColumn = 'event';
  static const fromColumn = 'from';
  static const toColumn = 'to';
  static const ratingColumn = 'rating';
  static const commentColumn = 'comment';
  static const respondentColumn = 'respondent';
  static const anonymousColumn = 'anonymous';
  static const submittedAtColumn = 'submitted_at';
  static const updatedAtColumn = 'updated_at';
  static const _modelReferenceColumn = '_feedback_model';

  @override
  final int id;
  final String event;
  final String from;
  final String to;
  final String rating;
  final String comment;
  final String respondent;
  final String anonymous;
  final String submittedAt;
  final String updatedAt;
  final Future<void> Function(int feedbackId) _delete;

  EventFeedbackAdminRow({
    required this.id,
    required this.event,
    required this.from,
    required this.to,
    required this.rating,
    required this.comment,
    required this.respondent,
    required this.anonymous,
    required this.submittedAt,
    required this.updatedAt,
    required Future<void> Function(int feedbackId) delete,
  }) : _delete = delete;

  factory EventFeedbackAdminRow.fromExport(
    Map<String, dynamic> json, {
    required Future<void> Function(int feedbackId) delete,
  }) {
    final isAnonymous = json['is_anonymous'] == true;
    return EventFeedbackAdminRow(
      id: (json[feedbackIdColumn] as num).toInt(),
      event: (json['event_title'] ?? '').toString(),
      from: (json['event_start_time'] ?? '').toString(),
      to: (json['event_end_time'] ?? '').toString(),
      rating: EventFeedbackStrings.ratingLabel(
        (json['rating'] ?? '').toString(),
      ),
      comment: (json['note'] ?? '').toString(),
      respondent: isAnonymous
          ? EventFeedbackStrings.anonymous
          : (json['user_name'] ?? '').toString(),
      anonymous:
          isAnonymous ? EventFeedbackStrings.yes : EventFeedbackStrings.no,
      submittedAt: (json['created_at'] ?? '').toString(),
      updatedAt: (json['updated_at'] ?? '').toString(),
      delete: delete,
    );
  }

  static EventFeedbackAdminRow fromPlutoJson(Map<String, dynamic> json) =>
      json[_modelReferenceColumn] as EventFeedbackAdminRow;

  @override
  TrinaRow toTrinaRow(BuildContext context) => TrinaRow(cells: {
        feedbackIdColumn: TrinaCell(value: id),
        eventColumn: TrinaCell(value: event),
        fromColumn: TrinaCell(value: from),
        toColumn: TrinaCell(value: to),
        ratingColumn: TrinaCell(value: rating),
        commentColumn: TrinaCell(value: comment),
        respondentColumn: TrinaCell(value: respondent),
        anonymousColumn: TrinaCell(value: anonymous),
        submittedAtColumn: TrinaCell(value: submittedAt),
        updatedAtColumn: TrinaCell(value: updatedAt),
        _modelReferenceColumn: TrinaCell(value: this),
      });

  @override
  Future<void> deleteMethod(BuildContext context) => _delete(id);

  @override
  Future<void> updateMethod(BuildContext context) async {}

  @override
  String toBasicString() => event;
}
