import 'package:flutter/material.dart';
import 'package:fstapp/components/_shared/common_strings.dart';
import 'package:fstapp/components/event_feedback/db_event_feedback.dart';
import 'package:fstapp/components/event_feedback/event_feedback_admin_row.dart';
import 'package:fstapp/components/event_feedback/event_feedback_strings.dart';
import 'package:fstapp/components/single_data_grid/data_grid_action.dart';
import 'package:fstapp/components/single_data_grid/single_data_grid_controller.dart';
import 'package:fstapp/components/single_data_grid/single_table_data_grid.dart';
import 'package:fstapp/data_services/rights_service.dart';
import 'package:trina_grid/trina_grid.dart';

/// Program → Feedback admin subtab, implemented through the canonical admin
/// data-grid lifecycle (load → mark changes → save/discard).
class EventFeedbackAdminContent extends StatefulWidget {
  const EventFeedbackAdminContent({
    super.key,
    this.loadOverride,
    this.deleteOverride,
  });

  final Future<List<Map<String, dynamic>>> Function(int occasionId)?
      loadOverride;
  final Future<void> Function(int occasionId, int feedbackId)? deleteOverride;

  @override
  State<EventFeedbackAdminContent> createState() =>
      _EventFeedbackAdminContentState();
}

class _EventFeedbackAdminContentState extends State<EventFeedbackAdminContent> {
  SingleDataGridController<EventFeedbackAdminRow>? _controller;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _controller ??= SingleDataGridController<EventFeedbackAdminRow>(
      context: context,
      loadData: _loadRows,
      fromPlutoJson: EventFeedbackAdminRow.fromPlutoJson,
      firstColumnType: RightsService.isAdmin()
          ? DataGridFirstColumn.delete
          : DataGridFirstColumn.none,
      idColumn: EventFeedbackAdminRow.feedbackIdColumn,
      actionsExtended: DataGridActionsController(
        isAddActionPossible: () => false,
        areAllActionsEnabled: RightsService.isAdmin,
      ),
      exportOptions: ExportOptions(fileName: 'event_feedback'),
      columns: [
        TrinaColumn(
          hide: true,
          title: CommonStrings.id,
          field: EventFeedbackAdminRow.feedbackIdColumn,
          type: TrinaColumnType.number(),
          readOnly: true,
        ),
        _column(
            EventFeedbackAdminRow.eventColumn, EventFeedbackStrings.event, 240),
        _column(
            EventFeedbackAdminRow.fromColumn, EventFeedbackStrings.from, 130),
        _column(EventFeedbackAdminRow.toColumn, EventFeedbackStrings.to, 130),
        _column(EventFeedbackAdminRow.ratingColumn, EventFeedbackStrings.rating,
            110),
        _column(EventFeedbackAdminRow.commentColumn,
            EventFeedbackStrings.comment, 340),
        _column(EventFeedbackAdminRow.respondentColumn,
            EventFeedbackStrings.respondent, 180),
        _column(EventFeedbackAdminRow.anonymousColumn,
            EventFeedbackStrings.anonymous, 110),
        _column(EventFeedbackAdminRow.submittedAtColumn,
            EventFeedbackStrings.submittedAt, 145),
        _column(EventFeedbackAdminRow.updatedAtColumn,
            EventFeedbackStrings.updatedAt, 145),
      ],
    );
  }

  static TrinaColumn _column(String field, String title, double width) =>
      TrinaColumn(
        title: title,
        field: field,
        type: TrinaColumnType.text(),
        readOnly: true,
        enableEditingMode: false,
        width: width,
      );

  Future<List<EventFeedbackAdminRow>> _loadRows() async {
    final occasionId = RightsService.currentOccasionId();
    if (occasionId == null) return [];

    final rows = widget.loadOverride != null
        ? await widget.loadOverride!(occasionId)
        : await DbEventFeedback.exportForEdit(occasionId);

    return rows
        .map(
          (row) => EventFeedbackAdminRow.fromExport(
            row,
            delete: (feedbackId) =>
                widget.deleteOverride?.call(occasionId, feedbackId) ??
                DbEventFeedback.deleteForEdit(occasionId, feedbackId),
          ),
        )
        .toList();
  }

  @override
  Widget build(BuildContext context) =>
      SingleTableDataGrid<EventFeedbackAdminRow>(_controller!);
}
