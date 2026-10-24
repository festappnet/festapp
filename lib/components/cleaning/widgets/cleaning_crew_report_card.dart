import 'package:flutter/material.dart';
import 'package:fstapp/components/cleaning/cleaning_status.dart';
import 'package:fstapp/components/cleaning/cleaning_strings.dart';
import 'package:fstapp/components/cleaning/models/cleaning_place_status.dart';
import 'package:fstapp/components/cleaning/models/cleaning_report.dart';
import 'package:fstapp/theme_config.dart';
import 'package:intl/intl.dart';

/// Crew card for one problematic toilet: its open reports (type, note(s),
/// reporter, time) and a "Cleaned" button resolving them all at once.
class CleaningCrewReportCard extends StatelessWidget {
  final CleaningPlaceStatus place;
  final List<CleaningReport> reports;
  final VoidCallback onResolve;
  final void Function(CleaningReport) onBlock;

  const CleaningCrewReportCard({
    super.key,
    required this.place,
    required this.reports,
    required this.onResolve,
    required this.onBlock,
  });

  @override
  Widget build(BuildContext context) {
    final color = CleaningStatusHelper.color(place.status);
    final timeFmt = DateFormat.jm();
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: color, width: 2),
      ),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.wc, color: color),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    place.title,
                    style: const TextStyle(
                        fontWeight: FontWeight.bold, fontSize: 18),
                  ),
                ),
                FilledButton.icon(
                  onPressed: onResolve,
                  icon: const Icon(Icons.check),
                  label: Text(CleaningStrings.markCleaned),
                ),
              ],
            ),
            const SizedBox(height: 8),
            for (final r in reports)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 4),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Container(
                          width: 10,
                          height: 10,
                          decoration: BoxDecoration(
                            color: CleaningStatusHelper.colorForType(
                                r.problemType),
                            shape: BoxShape.circle,
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            CleaningStrings.problemLabel(r.problemType),
                            style: const TextStyle(fontWeight: FontWeight.w600),
                          ),
                        ),
                        Text(
                          "${timeFmt.format(r.createdAt)} · ${r.createdByName ?? CleaningStrings.anonymous}",
                          style: TextStyle(
                              fontSize: 12,
                              color: ThemeConfig.grey600(context)),
                        ),
                        // Blocked reporters get a chip; others an overflow menu
                        // with the (destructive) "block reporter" action.
                        if (r.createdByBlocked)
                          Padding(
                            padding: const EdgeInsets.only(left: 6),
                            child: Icon(Icons.block,
                                size: 16,
                                color: Theme.of(context).colorScheme.error),
                          )
                        else if (r.createdBy != null)
                          SizedBox(
                            width: 32,
                            height: 32,
                            child: PopupMenuButton<String>(
                              tooltip: CleaningStrings.blockReporter,
                              icon: const Icon(Icons.more_vert, size: 18),
                              padding: EdgeInsets.zero,
                              onSelected: (_) => onBlock(r),
                              itemBuilder: (_) => [
                                PopupMenuItem(
                                  value: 'block',
                                  child: Row(
                                    children: [
                                      Icon(Icons.block,
                                          size: 18,
                                          color: Theme.of(context)
                                              .colorScheme
                                              .error),
                                      const SizedBox(width: 8),
                                      Text(CleaningStrings.blockReporter),
                                    ],
                                  ),
                                ),
                              ],
                            ),
                          ),
                      ],
                    ),
                    for (final note in [
                      if (r.note != null) r.note!,
                      ...r.extraNotes
                    ])
                      Padding(
                        padding: const EdgeInsets.only(left: 18, top: 2),
                        child: Text('„$note"',
                            style:
                                const TextStyle(fontStyle: FontStyle.italic)),
                      ),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }
}
