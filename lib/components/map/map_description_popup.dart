import 'package:flutter/material.dart';
import 'package:fstapp/components/cleaning/cleaning_status.dart';
import 'package:fstapp/components/cleaning/cleaning_strings.dart';
import 'package:fstapp/data_services/rights_service.dart';
import 'package:fstapp/components/map/map_place_model.dart';
import 'package:fstapp/components/map/map_strings.dart';
import 'package:fstapp/components/html/html_view.dart';

class MapDescriptionPopup extends StatefulWidget {
  final MapPlaceModel place;
  final bool isEditing;
  final VoidCallback onClose;
  final VoidCallback? onNavigate;
  final VoidCallback? onChangePosition;

  /// For toilet places with the cleaning feature on: the derived status (drives
  /// a colored chip) and the "report a problem" action. Null for other places.
  final CleaningStatus? cleaningStatus;
  final VoidCallback? onReportCleaning;

  const MapDescriptionPopup({
    required this.place,
    required this.isEditing,
    required this.onClose,
    this.onNavigate,
    this.onChangePosition,
    this.cleaningStatus,
    this.onReportCleaning,
    super.key,
  });

  @override
  State<StatefulWidget> createState() => _MapDescriptionPopupState();
}

class _MapDescriptionPopupState extends State<MapDescriptionPopup> {
  @override
  Widget build(BuildContext context) {
    return Card(
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          _cardDescription(context),
        ],
      ),
    );
  }

  Widget _cardDescription(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(10),
      child: Container(
        constraints: const BoxConstraints(minWidth: 100, maxWidth: 300),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisAlignment: MainAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Text(
                    widget.place.title,
                    overflow: TextOverflow.fade,
                    softWrap: true,
                    style: const TextStyle(
                      fontWeight: FontWeight.w500,
                      fontSize: 18,
                    ),
                  ),
                ),
                IconButton(
                  visualDensity: VisualDensity.compact,
                  tooltip: MaterialLocalizations.of(context).closeButtonTooltip,
                  onPressed: widget.onClose,
                  icon: const Icon(Icons.close),
                ),
              ],
            ),
            const Padding(padding: EdgeInsets.symmetric(vertical: 4.0)),
            if (widget.onNavigate != null) ...[
              FilledButton.tonalIcon(
                onPressed: widget.onNavigate,
                icon: const Icon(Icons.directions_outlined),
                label: Text(MapStrings.navigate),
              ),
              const SizedBox(height: 8),
            ],
            if (widget.cleaningStatus != null) _buildCleaningSection(context),
            Visibility(
                visible: RightsService.isEditor() ||
                    (RightsService.isGroupAdmin() &&
                        RightsService.currentUserGroup()!.place!.id ==
                            widget.place.id &&
                        RightsService.currentUserGroup()!
                            .place!
                            .isPrivateGroupLocation),
                child: TextButton.icon(
                    icon: const Icon(Icons.edit),
                    onPressed:
                        widget.isEditing || widget.onChangePosition == null
                            ? null
                            : widget.onChangePosition,
                    label: Text(MapStrings.changeLocation))),
            HtmlView(
              html: widget.place.description ?? "",
              isSelectable: true,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildCleaningSection(BuildContext context) {
    final status = widget.cleaningStatus!;
    final color = CleaningStatusHelper.color(status);
    final isOk = status == CleaningStatus.green;
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 12,
                height: 12,
                decoration: BoxDecoration(color: color, shape: BoxShape.circle),
              ),
              const SizedBox(width: 6),
              Text(
                isOk
                    ? CleaningStrings.statusOk
                    : CleaningStrings.problemLabel(
                        CleaningStatusHelper.codeOf(status)),
                style: TextStyle(color: color, fontWeight: FontWeight.w600),
              ),
            ],
          ),
          const SizedBox(height: 4),
          if (widget.onReportCleaning != null)
            TextButton.icon(
              icon: const Icon(Icons.report_problem_outlined),
              onPressed: widget.onReportCleaning,
              label: Text(CleaningStrings.reportProblem),
            ),
        ],
      ),
    );
  }
}
